#!/usr/bin/env bash
# Regression test for the GitHub identity wrappers in private_dot_local/bin.
#
# mrshll-agent is the ambient identity on serveserve: agent-gh uses its token
# from gh's own store without passh, and falls back to passh only when that
# token is missing. Acting as Marsh (mgh) always goes through passh. Neither
# ever hands a command Marsh's stored login.
#
# Runs the scripts against stub gh and passh in a throwaway HOME; no network,
# no 1Password, nothing touches the real gh config.
#
# Usage: tests/gh_identity_test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_GH="$REPO_DIR/private_dot_local/bin/executable_agent-gh"
MGH="$REPO_DIR/private_dot_local/bin/executable_mgh"
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
    "api user") cat "$STUB/login-as" 2>/dev/null || echo mrshll-agent ;;
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
printf 'GH_TOKEN=%s\nGITHUB_TOKEN=%s\nPASSH_NO_FALLBACK=%s\n' "${GH_TOKEN-}" "${GITHUB_TOKEN-}" "${PASSH_NO_FALLBACK-}"
git config --get-all url.https://github.com/.insteadOf || true
EOF
chmod +x "$WORK/bin/"*

run() {
    rm -f "$STUB/gh.log" "$STUB/passh.log"
    env -u GH_TOKEN -u GITHUB_TOKEN HOME="$WORK/home" STUB="$WORK" \
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

out=$(run env GH_TOKEN=marsh-from-mgh GITHUB_TOKEN=marsh-too bash "$AGENT_GH" probe)
check "agent-gh: an inherited GH_TOKEN is neither used nor passed on" \
    'grep -qx "GH_TOKEN=agent-stored-token" <<<"$out" && grep -q "|GH_TOKEN=$" "$WORK/gh.log"'
check "agent-gh: an inherited GITHUB_TOKEN is dropped" 'grep -qx "GITHUB_TOKEN=" <<<"$out"'

# --- agent-gh, nothing stored ------------------------------------------------
rm -f "$WORK/stored"
out=$(run bash "$AGENT_GH" probe)
check "agent-gh: no stored token, passh for the agent item" \
    'grep -qx "GH_TOKEN=op://Private/Github agent/Token" "$WORK/passh.log"'
check "agent-gh: passh may not fall back to a password prompt" 'grep -qx "PASSH_NO_FALLBACK=1" "$WORK/passh.log"'
check "agent-gh: command gets the passh-resolved agent token" \
    'grep -qx "GH_TOKEN=resolved:op://Private/Github agent/Token" <<<"$out" && grep -qx "PASSH_NO_FALLBACK=" <<<"$out"'

# --- agent-gh --seed ---------------------------------------------------------
rm -f "$WORK/login-stdin" "$WORK/stored"
run bash "$AGENT_GH" --seed >/dev/null 2>&1 && seeded=0 || seeded=$?
check "agent-gh --seed: succeeds" '[ "$seeded" -eq 0 ]'
check "agent-gh --seed: checks whose token it is before storing it" \
    'grep -q "^api user --jq .login|GH_TOKEN=resolved:op://Private/Github agent/Token$" "$WORK/gh.log"'
check "agent-gh --seed: one passh call for the agent item, not as GH_TOKEN" \
    '[ "$(grep -c "op://" "$WORK/passh.log")" -eq 1 ] && grep -q "=op://Private/Github agent/Token$" "$WORK/passh.log" && ! grep -q "^GH_TOKEN=" "$WORK/passh.log"'
check "agent-gh --seed: gh stores it in its file, 0600, over https" \
    'grep -q "^auth login --hostname github.com --git-protocol https --insecure-storage --with-token|GH_TOKEN=$" "$WORK/gh.log"'
check "agent-gh --seed: token arrives on stdin" '[ "$(cat "$WORK/login-stdin")" = "resolved:op://Private/Github agent/Token" ]'
echo mrshll > "$WORK/login-as"
run bash "$AGENT_GH" --seed >/dev/null 2>&1 && seeded=0 || seeded=$?
check "agent-gh --seed: refuses a token that is not mrshll-agent's, storing nothing" \
    '[ "$seeded" -ne 0 ] && ! grep -q "^auth login" "$WORK/gh.log"'
rm -f "$WORK/login-as"

# --- mgh ---------------------------------------------------------------------
touch "$WORK/stored"
out=$(run bash "$MGH" pr list)
check "mgh: gh as Marsh, token from passh, never the agent's" \
    'grep -q "^GH_TOKEN=op://" "$WORK/passh.log" && ! grep -q "Github agent" "$WORK/passh.log" && grep -q "^gh-ran pr list GH_TOKEN=resolved:op://" <<<"$out"'
out=$(run env GH_TOKEN=agent-stored-token bash "$MGH" git config --get-all url.https://github.com/.insteadOf)
check "mgh git: token from passh" 'grep -q "^GH_TOKEN=op://" "$WORK/passh.log"'
check "mgh git: SSH remotes go over HTTPS, so git uses the injected token" 'grep -qx "git@github.com:" <<<"$out"'
# A passh that resolves the item to nothing.
mkdir -p "$WORK/emptybin"
printf '#!/usr/bin/env bash\nshift 3; GH_TOKEN= exec "$@"\n' > "$WORK/emptybin/passh"
chmod +x "$WORK/emptybin/passh"
out=$(run env PATH="$WORK/emptybin:$WORK/bin:/usr/bin:/bin" bash "$MGH" pr list 2>/dev/null) && rc=0 || rc=$?
check "mgh: an empty token fails rather than falling back to the stored agent login" \
    '[ "$rc" -ne 0 ] && ! grep -q "^gh-ran" <<<"$out"'
run bash "$MGH" >/dev/null 2>&1 && rc=0 || rc=$?
check "mgh: no arguments is a usage error" '[ "$rc" -eq 64 ] && [ ! -e "$WORK/passh.log" ]'

echo
[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failure(s)" >&2; exit 1; }
