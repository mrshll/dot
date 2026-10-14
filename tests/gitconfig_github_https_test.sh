#!/usr/bin/env bash
# Regression test for the GitHub SSH->HTTPS rewrite in dot_gitconfig.tmpl.
#
# serveserve holds no GitHub login of Marsh's, so its SSH remotes must go over
# HTTPS, where gh's stored login (mrshll-agent) answers. Every other machine
# keeps SSH remotes as they are.
#
# Usage: tests/gitconfig_github_https_test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
pass() { printf 'ok:   %s\n' "$*"; }

# render OS IS_SERVER: path to ~/.gitconfig as rendered for that machine.
render() {
    local cfg="$WORK/chezmoi-$1-$2.toml" out="$WORK/gitconfig-$1-$2"
    printf '[data]\n  hostname = "test"\n  os = "%s"\n  is_server = %s\n  has_op = false\n' "$1" "$2" > "$cfg"
    chezmoi execute-template --file "$REPO_DIR/dot_gitconfig.tmpl" \
        --source "$REPO_DIR" --config "$cfg" \
        --override-data "{\"chezmoi\":{\"os\":\"$1\"}}" > "$out"
    printf '%s' "$out"
}

# rewritten CONFIG URL: what git fetches/pushes for URL under CONFIG.
rewritten() {
    GIT_CONFIG_GLOBAL="$1" GIT_CONFIG_NOSYSTEM=1 git ls-remote --get-url "$2"
}

cfg=$(render linux true)
for url in git@github.com:mrshll/dot.git ssh://git@github.com/mrshll/dot.git; do
    got=$(rewritten "$cfg" "$url")
    [ "$got" = https://github.com/mrshll/dot.git ] && pass "serveserve: $url goes over HTTPS" \
        || fail "serveserve: $url became '$got'"
done
got=$(GIT_CONFIG_GLOBAL="$cfg" GIT_CONFIG_NOSYSTEM=1 git config --get-all credential.https://github.com.helper | tail -n1)
[ "$got" = "!/usr/bin/gh auth git-credential" ] && pass "serveserve: HTTPS asks gh for the credential" \
    || fail "serveserve: github.com helper is '$got'"

for combo in "darwin false" "linux false"; do
    set -- $combo
    cfg=$(render "$1" "$2")
    got=$(rewritten "$cfg" git@github.com:mrshll/dot.git)
    [ "$got" = git@github.com:mrshll/dot.git ] && pass "$1 (server=$2): SSH remotes untouched" \
        || fail "$1 (server=$2): SSH remote became '$got'"
done

echo
[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failure(s)" >&2; exit 1; }
