#!/usr/bin/env bash
# Regression test for the GitHub SSH->HTTPS rewrite.
#
# Only agents' git (dot_config/git/agent.gitconfig.tmpl, their
# GIT_CONFIG_GLOBAL on serveserve) sends SSH remotes over HTTPS, where gh's
# agent login (GH_CONFIG_DIR=~/.config/gh-agent) answers. Marsh's own
# ~/.gitconfig keeps SSH remotes on every machine, so his pushes use his key.
#
# Usage: tests/gitconfig_github_https_test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
pass() { printf 'ok:   %s\n' "$*"; }

# render TEMPLATE OS IS_SERVER: path to TEMPLATE as rendered for that machine.
render() {
    local cfg="$WORK/chezmoi-$2-$3.toml" out="$WORK/$(basename "$1")-$2-$3"
    printf '[data]\n  hostname = "test"\n  os = "%s"\n  is_server = %s\n  has_op = false\n' "$2" "$3" > "$cfg"
    chezmoi execute-template --file "$REPO_DIR/$1" \
        --source "$REPO_DIR" --config "$cfg" \
        --override-data "{\"chezmoi\":{\"os\":\"$2\"}}" > "$out"
    printf '%s' "$out"
}

# rewritten CONFIG URL: what git fetches/pushes for URL under CONFIG.
rewritten() {
    GIT_CONFIG_GLOBAL="$1" GIT_CONFIG_NOSYSTEM=1 git ls-remote --get-url "$2"
}

cfg=$(render dot_config/git/agent.gitconfig.tmpl linux true)
for url in git@github.com:mrshll/dot.git ssh://git@github.com/mrshll/dot.git; do
    got=$(rewritten "$cfg" "$url")
    [ "$got" = https://github.com/mrshll/dot.git ] && pass "agents: $url goes over HTTPS" \
        || fail "agents: $url became '$got'"
done
got=$(GIT_CONFIG_GLOBAL="$cfg" GIT_CONFIG_NOSYSTEM=1 git config --get-all credential.https://github.com.helper | tail -n1)
[ "$got" = "!/usr/bin/gh auth git-credential" ] && pass "agents: HTTPS asks gh for the credential" \
    || fail "agents: github.com helper is '$got'"

for combo in "linux true" "darwin false" "linux false"; do
    set -- $combo
    cfg=$(render dot_gitconfig.tmpl "$1" "$2")
    for url in git@github.com:mrshll/dot.git ssh://git@github.com/mrshll/dot.git; do
        got=$(rewritten "$cfg" "$url")
        [ "$got" = "$url" ] && pass "Marsh, $1 (server=$2): $url untouched" \
            || fail "Marsh, $1 (server=$2): $url became '$got'"
    done
done

echo
[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failure(s)" >&2; exit 1; }
