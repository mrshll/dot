#!/usr/bin/env bash
# Regression test for agent-gh (private_dot_local/bin).
#
# agent-gh uses mrshll-agent's token from the agents' gh config
# (~/.config/gh-agent) without passh, and falls back to passh only when that
# token is missing. It never hands a command Marsh's login from ~/.config/gh,
# and git authenticates with its token whatever credential helper a checkout
# configures.
#
# Runs the scripts against stub gh and passh in a throwaway HOME; no network,
# no 1Password, nothing touches the real gh config.
#
# Usage: tests/gh_identity_test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_GH="$REPO_DIR/private_dot_local/bin/executable_agent-gh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
pass() { printf 'ok:   %s\n' "$*"; }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

mkdir -p "$WORK/bin" "$WORK/home"

# gh stub. The stored login is mrshll-agent's only when $WORK/stored exists;
# the active account (no --user) is always Marsh's, as before the switch.
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s|GH_TOKEN=%s\n' "$*" "${GH_TOKEN-}" >> "$STUB/gh.log"
printf 'GH_HOST=%s GH_CONFIG_DIR=%s\n' "${GH_HOST-}" "${GH_CONFIG_DIR-}" >> "$STUB/gh-env.log"
case "$1 $2" in
    "auth token")
        case " $* " in
            *" --user mrshll-agent "*)
                [ -e "$STUB/stored" ] || { echo "no oauth token found" >&2; exit 1; }
                [ -z "${GH_TOKEN-}" ] || { echo "GH_TOKEN overrides the store" >&2; printf '%s\n' "$GH_TOKEN"; exit 0; }
                echo agent-stored-token ;;
            *) echo marsh-stored-token ;;
        esac ;;
    "auth login")
        [ -z "${GH_TOKEN-}${GITHUB_TOKEN-}" ] || exit 1
        cat > "$STUB/login-stdin"; touch "$STUB/stored" ;;
    "auth git-credential")
        # Like gh: hands git whatever token gh would use.
        cat >/dev/null
        printf 'protocol=https\nhost=github.com\nusername=x-access-token\npassword=%s\n' "${GH_TOKEN-}" ;;
    "api --hostname")
        [ "$3 $4" = "github.com user" ] || { echo "not github.com" >&2; exit 1; }
        cat "$STUB/login-as" 2>/dev/null || echo mrshll-agent ;;
    *) printf 'gh-ran %s GH_TOKEN=%s\n' "$*" "${GH_TOKEN-}" ;;
esac
EOF
# passh stub: logs the env-file and resolves op:// refs to "resolved:<ref>".
cat > "$WORK/bin/passh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = run ] || exit 2
envfile=$(cat "${2#--env-file=}"); shift 3  # a pipe: read it once
printf '%s\nPASSH_NO_FALLBACK=%s\n' "$envfile" "${PASSH_NO_FALLBACK-}" >> "$STUB/passh.log"
while IFS='=' read -r name ref; do export "$name=resolved:$ref"; done <<<"$envfile"
exec "$@"
EOF
# probe: what a wrapped command sees.
cat > "$WORK/bin/probe" <<'EOF'
#!/usr/bin/env bash
printf 'GH_TOKEN=%s\nGITHUB_TOKEN=%s\nPASSH_NO_FALLBACK=%s\nGH_CONFIG_DIR=%s\n' "${GH_TOKEN-}" "${GITHUB_TOKEN-}" "${PASSH_NO_FALLBACK-}" "${GH_CONFIG_DIR-}"
git config --get-all url.https://github.com/.insteadOf || true
EOF
# A checkout-level helper that would answer with some other account.
cat > "$WORK/bin/other-helper" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo "$1" >> "$STUB/other-helper.log"
printf 'username=someone-else\npassword=checkout-helper-token\n'
EOF
chmod +x "$WORK/bin/"*
# A passh that resolves the item to nothing.
mkdir -p "$WORK/emptybin"
printf '#!/usr/bin/env bash\nshift 3; GH_TOKEN= exec "$@"\n' > "$WORK/emptybin/passh"
chmod +x "$WORK/emptybin/passh"
# ~/.gitconfig's GitHub helper, as dot_gitconfig.tmpl renders it (gh on PATH).
printf '[credential "https://github.com"]\n\thelper =\n\thelper = !gh auth git-credential\n' \
    > "$WORK/home/.gitconfig"
git init -q "$WORK/repo"
git -C "$WORK/repo" config credential.https://github.com.helper ""
git -C "$WORK/repo" config --add credential.https://github.com.helper "!$WORK/bin/other-helper"
git -C "$WORK/repo" config credential.helper "!$WORK/bin/other-helper"
git -C "$WORK/repo" config credential.https://github.com/mrshll.helper "!$WORK/bin/other-helper"
# credential WRAPPER...: the password git would push github.com/mrshll/dot
# with, path-scoped helpers included, after which git stores it. The checkout's
# helper must see neither.
credential() {
    rm -f "$STUB/other-helper.log"
    local filled
    filled=$(printf 'protocol=https\nhost=github.com\npath=mrshll/dot.git\n\n' |
        run "$@" git -C "$WORK/repo" -c credential.useHttpPath=true credential fill 2>/dev/null)
    printf '%s\n\n' "$filled" |
        run "$@" git -C "$WORK/repo" -c credential.useHttpPath=true credential approve 2>/dev/null
    [ ! -e "$STUB/other-helper.log" ] || echo "checkout helper ran: $(tr '\n' ' ' < "$STUB/other-helper.log")"
    sed -n 's/^password=//p' <<<"$filled"
}

run() {
    rm -f "$STUB/gh.log" "$STUB/gh-env.log" "$STUB/passh.log"
    env -u GH_TOKEN -u GITHUB_TOKEN HOME="$WORK/home" STUB="$WORK" GIT_CONFIG_NOSYSTEM=1 \
        PATH="$WORK/bin:/usr/bin:/bin" "$@"
}
export STUB="$WORK"

# --- agent-gh, token stored --------------------------------------------------
touch "$WORK/stored"
out=$(run bash "$AGENT_GH" probe)
check "agent-gh: stored token, no passh" '[ ! -e "$WORK/passh.log" ]'
check "agent-gh: command gets the stored agent token" 'grep -qx "GH_TOKEN=agent-stored-token" <<<"$out"'
check "agent-gh: SSH remotes go over HTTPS" 'grep -qx "git@github.com:" <<<"$out"'
check "agent-gh: looks the token up by user, never the active account" \
    'grep -q "^auth token --hostname github.com --user mrshll-agent|" "$WORK/gh.log" && ! grep -q "marsh" <<<"$out"'

out=$(run env GH_TOKEN=marsh-inherited GITHUB_TOKEN=marsh-too GH_CONFIG_DIR="$WORK/elsewhere" bash "$AGENT_GH" probe)
check "agent-gh: looks in the agents' config --seed wrote, whatever GH_CONFIG_DIR is inherited" \
    '[ "$(head -n1 "$WORK/gh-env.log")" = "GH_HOST= GH_CONFIG_DIR=$WORK/home/.config/gh-agent" ]'
check "agent-gh: the command gets the agents' gh config, not Marsh's" \
    'grep -qx "GH_CONFIG_DIR=$WORK/home/.config/gh-agent" <<<"$out"'
check "agent-gh: an inherited GH_TOKEN is neither used nor passed on" \
    'grep -qx "GH_TOKEN=agent-stored-token" <<<"$out" && grep -q "|GH_TOKEN=$" "$WORK/gh.log"'
check "agent-gh: an inherited GITHUB_TOKEN is dropped" 'grep -qx "GITHUB_TOKEN=" <<<"$out"'

got=$(credential bash "$AGENT_GH")
check "agent-gh git: pushes with the agent token, not a checkout's own helper" '[ "$got" = agent-stored-token ]'

# --- agent-gh, nothing stored ------------------------------------------------
rm -f "$WORK/stored"
out=$(run bash "$AGENT_GH" probe)
check "agent-gh: no stored token, passh for the agent item" \
    'grep -qx "GH_TOKEN=op://Private/Github agent/Token" "$WORK/passh.log"'
check "agent-gh: passh may not fall back to a password prompt" 'grep -qx "PASSH_NO_FALLBACK=1" "$WORK/passh.log"'
check "agent-gh: command gets the passh-resolved agent token" \
    'grep -qx "GH_TOKEN=resolved:op://Private/Github agent/Token" <<<"$out" && grep -qx "PASSH_NO_FALLBACK=" <<<"$out"'

out=$(run env PATH="$WORK/emptybin:$WORK/bin:/usr/bin:/bin" bash "$AGENT_GH" probe 2>/dev/null) && rc=0 || rc=$?
check "agent-gh: an empty token from passh fails rather than running the command" \
    '[ "$rc" -ne 0 ] && ! grep -q "^GH_TOKEN=" <<<"$out"'
out=$(run env GH_CONFIG_DIR="$WORK/elsewhere" bash "$AGENT_GH" probe)
check "agent-gh: passh's command gets the agents' gh config too" \
    'grep -qx "GH_CONFIG_DIR=$WORK/home/.config/gh-agent" <<<"$out"'

# --- agent-gh --seed ---------------------------------------------------------
rm -f "$WORK/login-stdin" "$WORK/stored"
run env GH_HOST=ghe.example.com GH_CONFIG_DIR="$WORK/elsewhere" bash "$AGENT_GH" --seed >/dev/null 2>&1 && seeded=0 || seeded=$?
check "agent-gh --seed: succeeds" '[ "$seeded" -eq 0 ]'
check "agent-gh --seed: github.com and the agents' gh config, whatever was inherited" \
    '[ "$(sort -u "$WORK/gh-env.log")" = "GH_HOST= GH_CONFIG_DIR=$WORK/home/.config/gh-agent" ]'
check "agent-gh --seed: the agents' config dir is private" \
    '[ "$(stat -c %a "$WORK/home/.config/gh-agent")" = 700 ]'
check "agent-gh --seed: checks whose token it is before storing it" \
    'grep -q "^api --hostname github.com user --jq .login|GH_TOKEN=resolved:op://Private/Github agent/Token$" "$WORK/gh.log"'
check "agent-gh --seed: one passh call for the agent item, not as GH_TOKEN" \
    '[ "$(grep -c "op://" "$WORK/passh.log")" -eq 1 ] && grep -q "=op://Private/Github agent/Token$" "$WORK/passh.log" && ! grep -q "^GH_TOKEN=" "$WORK/passh.log"'
check "agent-gh --seed: gh stores it as a plain file, not a keyring, over https" \
    'grep -q "^auth login --hostname github.com --git-protocol https --insecure-storage --with-token|GH_TOKEN=$" "$WORK/gh.log"'
check "agent-gh --seed: token arrives on stdin" '[ "$(cat "$WORK/login-stdin")" = "resolved:op://Private/Github agent/Token" ]'
echo mrshll > "$WORK/login-as"
run bash "$AGENT_GH" --seed >/dev/null 2>&1 && seeded=0 || seeded=$?
check "agent-gh --seed: refuses a token that is not mrshll-agent's, storing nothing" \
    '[ "$seeded" -ne 0 ] && ! grep -q "^auth login" "$WORK/gh.log"'
rm -f "$WORK/login-as"

echo
[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failure(s)" >&2; exit 1; }
