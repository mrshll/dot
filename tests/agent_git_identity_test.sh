#!/usr/bin/env bash
# Regression test: on serveserve, gh and git run by an agent (Claude Code,
# Codex) act, author and sign as mrshll-agent, while Marsh's own shells keep him.
#
# The split is GIT_CONFIG_GLOBAL=~/.config/git/agent.gitconfig and
# GH_CONFIG_DIR=~/.config/gh-agent, which the Claude Code settings and Codex
# config put in the environment of the commands those agents run, on
# serveserve only. Renders the modify scripts and both
# gitconfigs into a throwaway directory; nothing touches the real home.
#
# Usage: tests/agent_git_identity_test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
AGENT_CONFIG="$HOME/.config/git/agent.gitconfig"
AGENT_GH="$HOME/.config/gh-agent"

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
pass() { printf 'ok:   %s\n' "$*"; }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

# render TEMPLATE IS_SERVER: the template as chezmoi renders it on Linux.
render() {
    local cfg="$WORK/chezmoi-$2.toml"
    printf '[data]\n  hostname = "test"\n  os = "linux"\n  is_server = %s\n  has_op = false\n' "$2" > "$cfg"
    chezmoi execute-template --file "$REPO_DIR/$1" --source "$REPO_DIR" --config "$cfg" \
        --override-data '{"chezmoi":{"os":"linux"}}'
}
toml() { uv run --no-project python -I -c 'import json, sys, tomllib; print(json.dumps(tomllib.load(sys.stdin.buffer)))'; }

# --- Claude Code settings ----------------------------------------------------
for server in true false; do render dot_claude/modify_settings.json.tmpl "$server" > "$WORK/claude-$server.sh"; done
live='{"theme":"dark","env":{"KEPT":"1"}}'
out=$(bash "$WORK/claude-true.sh" <<<"$live")
check "claude, serveserve: commands get the agent gitconfig" \
    '[ "$(jq -r .env.GIT_CONFIG_GLOBAL <<<"$out")" = "$AGENT_CONFIG" ]'
check "claude, serveserve: commands get the agents' gh config" \
    '[ "$(jq -r .env.GH_CONFIG_DIR <<<"$out")" = "$AGENT_GH" ]'
check "claude, serveserve: env set by hand survives" '[ "$(jq -r .env.KEPT <<<"$out")" = 1 ]'
check "claude, serveserve: other live settings survive" '[ "$(jq -r .theme <<<"$out")" = dark ]'
out=$(bash "$WORK/claude-true.sh" </dev/null)
check "claude, serveserve: a fresh machine gets it too" \
    '[ "$(jq -cS .env <<<"$out")" = "{\"GH_CONFIG_DIR\":\"$AGENT_GH\",\"GIT_CONFIG_GLOBAL\":\"$AGENT_CONFIG\"}" ]'
out=$(bash "$WORK/claude-false.sh" <<<"$live")
check "claude, elsewhere: no agent gitconfig, env untouched" '[ "$(jq -c .env <<<"$out")" = "{\"KEPT\":\"1\"}" ]'
out=$(bash "$WORK/claude-false.sh" <<<'{"theme":"dark"}')
check "claude, elsewhere: no env added" '[ "$(jq -c . <<<"$out" | jq "has(\"env\")")" = false ]'
out=$(bash "$WORK/claude-true.sh" <<<"$live" | bash "$WORK/claude-false.sh")
check "claude, rolled back: the agent values are removed, env set by hand stays" '[ "$(jq -c .env <<<"$out")" = "{\"KEPT\":\"1\"}" ]'
out=$(bash "$WORK/claude-false.sh" <<<'{"env":{"GH_CONFIG_DIR":"/mine"}}')
check "claude, elsewhere: a GH_CONFIG_DIR set by hand stays" '[ "$(jq -r .env.GH_CONFIG_DIR <<<"$out")" = /mine ]'

# --- Codex config ------------------------------------------------------------
for server in true false; do render dot_codex/modify_private_config.toml.tmpl "$server" > "$WORK/codex-$server.sh"; done
# Live configs, each valid TOML, holding an unrelated KEPT variable in a
# different spelling of shell_environment_policy.set.
mkdir -p "$WORK/live"
printf 'model = "kept"\n\n[shell_environment_policy.set]\nKEPT = "yes"\nGIT_CONFIG_GLOBAL = "/somewhere/else"\nGH_CONFIG_DIR = "/home/x/.config/gh"\n\n[mcp_servers.other]\nurl = "https://example.com/mcp"\n' > "$WORK/live/table.toml"
printf 'model = "kept"\n\n  [shell_environment_policy.set]  # indented\n  KEPT = "yes"\n' > "$WORK/live/indented.toml"
printf "model = 'kept'\n\n[shell_environment_policy.set]\nKEPT = 'yes'\n'GH_CONFIG_DIR' = '/old'\n\"GIT_CONFIG_GLOBAL\" = '/old'\n" > "$WORK/live/literal-keys.toml"
printf 'model = "kept"\n' > "$WORK/live/none.toml"
# A table header inside a multi-line string is text, not a table.
printf 'developer_instructions = """\nExample configuration:\n[shell_environment_policy.set]\nEXAMPLE = "sample"\n"""\nmodel = "kept"\n' > "$WORK/live/in-string.toml"
printf "notes = '''\n[shell_environment_policy.set]\n'''\n\n[shell_environment_policy.set]\nKEPT = 'yes'\n" > "$WORK/live/in-literal-string.toml"
# Forms the script does not edit: on serveserve, apply must fail rather than
# install a broken config or one without the agent identity.
printf 'model = "kept"\n\n[shell_environment_policy]\ninherit = "core"\nset = { KEPT = "yes" }\n' > "$WORK/live/inline.toml"
printf 'model = "kept"\nshell_environment_policy = { set = { KEPT = "yes" } }\n' > "$WORK/live/root-inline.toml"
printf 'model = "kept"\n\n[shell_environment_policy]\nset.KEPT = "yes"\n' > "$WORK/live/dotted.toml"
printf "model = 'kept'\n\n[shell_environment_policy]\n'set'.KEPT = 'yes'\n" > "$WORK/live/literal-dotted.toml"
printf 'model = "kept"\n\n[shell_environment_policy."set"]\nKEPT = "yes"\n' > "$WORK/live/quoted.toml"
printf 'model = "kept"\n\n[shell_environment_policy.set]\nKEPT = "yes"\nGH_CONFIG_DIR = """\n/old\n"""\n' > "$WORK/live/multiline.toml"
# json FILE: the TOML as JSON, Cloudflare MCP entries (managed here) left out.
json() { toml < "$1" | jq -cS 'del(.mcp_servers.cloudflare, .mcp_servers["cloudflare-docs"], .mcp_servers["cloudflare-bindings"], .mcp_servers["cloudflare-builds"], .mcp_servers["cloudflare-observability"]) | if .mcp_servers == {} then del(.mcp_servers) else . end'; }
for live in "$WORK"/live/*.toml; do
    name=$(basename "$live" .toml)
    json "$live" >/dev/null || { fail "codex fixture $name is not valid TOML"; continue; }
    for server in true false; do
        sh "$WORK/codex-$server.sh" < "$live" > "$WORK/out-$name-$server.toml" 2>"$WORK/err-$name-$server" && rc=0 || rc=$?
        case "$server-$name" in
            true-inline|true-root-inline|true-dotted|true-literal-dotted|true-quoted|true-multiline)
                [ "$rc" -ne 0 ] && grep -q "form this script does not edit" "$WORK/err-$name-$server" \
                    && pass "codex ($name): a form it does not edit fails the apply, with the reason" \
                    || fail "codex ($name): rc=$rc for a form it does not edit"
                continue ;;
        esac
        [ "$rc" -eq 0 ] || { fail "codex ($name, server=$server): exit $rc: $(cat "$WORK/err-$name-$server")"; continue; }
        if ! got=$(json "$WORK/out-$name-$server.toml" 2>/dev/null); then
            fail "codex ($name, server=$server): output is not valid TOML"; continue
        fi
        want=$(json "$live")
        case "$server-$name" in
            true-*)
                want=$(jq -cS --arg g "$AGENT_CONFIG" --arg h "$AGENT_GH" \
                    '.shell_environment_policy.set.GIT_CONFIG_GLOBAL = $g | .shell_environment_policy.set.GH_CONFIG_DIR = $h' <<<"$want") ;;
        esac
        [ "$got" = "$want" ] && pass "codex ($name, server=$server): only the managed keys change" \
            || fail "codex ($name, server=$server): got $got, want $want"
        sh "$WORK/codex-$server.sh" < "$WORK/out-$name-$server.toml" 2>/dev/null > "$WORK/again.toml"
        cmp -s "$WORK/out-$name-$server.toml" "$WORK/again.toml" || fail "codex ($name, server=$server): applying again changes it"
    done
done
# A live config that is already broken is not made worse or installed.
printf 'model = "kept"\nmodel = "twice"\n' | sh "$WORK/codex-true.sh" >/dev/null 2>"$WORK/err-broken" && rc=0 || rc=$?
check "codex, serveserve: a result that does not parse fails the apply" \
    '[ "$rc" -ne 0 ] && grep -q "not valid TOML" "$WORK/err-broken"'
# Rolling back (or any other machine): the keys this set are removed; the same
# keys holding something else, and everything else, stay.
sh "$WORK/codex-true.sh" < "$WORK/live/table.toml" | sh "$WORK/codex-false.sh" > "$WORK/rolled.toml"
check "codex, rolled back: the agent values are removed, everything else stays" \
    '[ "$(json "$WORK/rolled.toml")" = "$(json "$WORK/live/table.toml" | jq -cS "del(.shell_environment_policy.set.GIT_CONFIG_GLOBAL, .shell_environment_policy.set.GH_CONFIG_DIR)")" ]'
printf '[shell_environment_policy.set]\nGH_CONFIG_DIR = "/mine"\n' | sh "$WORK/codex-false.sh" > "$WORK/mine.toml"
check "codex, elsewhere: a GH_CONFIG_DIR set by hand stays" '[ "$(json "$WORK/mine.toml" | jq -r .shell_environment_policy.set.GH_CONFIG_DIR)" = /mine ]'
printf '[shell_environment_policy.set]\nGH_CONFIG_DIR = "/mine" # was "%s"\nGIT_CONFIG_GLOBAL = "%s"\n' "$AGENT_GH" "$AGENT_GH" | sh "$WORK/codex-false.sh" > "$WORK/mine.toml"
check "codex, elsewhere: only a key holding its own agent value goes, not one whose comment names it" \
    '[ "$(json "$WORK/mine.toml" | jq -c .shell_environment_policy.set)" = "{\"GH_CONFIG_DIR\":\"/mine\",\"GIT_CONFIG_GLOBAL\":\"$AGENT_GH\"}" ]'

# --- what git does with it ---------------------------------------------------
render dot_config/git/agent.gitconfig.tmpl true > "$WORK/agent.gitconfig"
render dot_gitconfig.tmpl true > "$WORK/gitconfig"
git init -q "$WORK/repo"
# ident CONFIG KEY: what git resolves KEY to with CONFIG as the global config.
ident() { GIT_CONFIG_GLOBAL="$1" GIT_CONFIG_NOSYSTEM=1 git -C "$WORK/repo" config --get "$2"; }
check "git, agent: authors as mrshll-agent" \
    '[ "$(ident "$WORK/agent.gitconfig" user.name)" = mrshll-agent ] && [ "$(ident "$WORK/agent.gitconfig" user.email)" = 337028807+mrshll-agent@users.noreply.github.com ]'
check "git, agent: signs with the agent key" \
    '[ "$(ident "$WORK/agent.gitconfig" user.signingkey)" = "$HOME/.ssh/mrshll_agent_signing_ed25519" ] && [ "$(ident "$WORK/agent.gitconfig" commit.gpgsign)" = true ]'
check "git, agent: GitHub credentials from gh's stored login, SSH remotes over HTTPS" \
    '[ "$(GIT_CONFIG_GLOBAL="$WORK/agent.gitconfig" git -C "$WORK/repo" config --get-all credential.https://github.com.helper | tail -n1)" = "!/usr/bin/gh auth git-credential" ] && [ "$(GIT_CONFIG_GLOBAL="$WORK/agent.gitconfig" git -C "$WORK/repo" ls-remote --get-url git@github.com:mrshll/dot.git)" = https://github.com/mrshll/dot.git ]'
check "git, Marsh's shell: still authors and signs as him" \
    '[ "$(ident "$WORK/gitconfig" user.name)" = mrsll ] && [ "$(ident "$WORK/gitconfig" user.signingkey)" = "$HOME/.ssh/id_ed25519" ]'

echo
[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failure(s)" >&2; exit 1; }
