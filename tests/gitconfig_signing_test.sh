#!/usr/bin/env bash
# Regression test for user.signingkey in dot_gitconfig.tmpl.
#
# Only serveserve has a resident signing key. Every other Linux box must name
# the 1Password key by its public literal, never by a path: mono's
# .devcontainer/initialize.sh copies whatever file a path-valued signingkey
# points at into the workspace, private keys included.
#
# Usage: tests/gitconfig_signing_test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ONEPASSWORD_KEY=$(awk '$NF == "1password" {print $2, $3}' "$REPO_DIR/dot_config/git/allowed_signers")

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
pass() { printf 'ok:   %s\n' "$*"; }

# signingkey OS IS_SERVER: user.signingkey as rendered for that machine.
signingkey() {
    local cfg="$WORK/chezmoi-$1-$2.toml"
    printf '[data]\n  hostname = "test"\n  os = "%s"\n  is_server = %s\n  has_op = false\n' "$1" "$2" > "$cfg"
    chezmoi execute-template --file "$REPO_DIR/dot_gitconfig.tmpl" \
        --source "$REPO_DIR" --config "$cfg" \
        --override-data "{\"chezmoi\":{\"os\":\"$1\"}}" > "$WORK/gitconfig-$1-$2"
    git config -f "$WORK/gitconfig-$1-$2" --get user.signingkey
}

[ -n "$ONEPASSWORD_KEY" ] && pass "allowed_signers has the 1Password key" \
    || fail "no 1password entry in allowed_signers"

got=$(signingkey darwin false)
[ "$got" = "$ONEPASSWORD_KEY" ] && pass "mac: signs with the 1Password key (unchanged)" \
    || fail "mac: signingkey is '$got'"

got=$(signingkey linux true)
[ "$got" = "$HOME/.ssh/id_ed25519" ] && pass "serveserve: signs with its resident key (unchanged)" \
    || fail "serveserve: signingkey is '$got'"

got=$(signingkey linux false)
[ "$got" = "key::$ONEPASSWORD_KEY" ] && pass "other linux: the 1Password public key, as a key:: literal" \
    || fail "other linux: signingkey is '$got'"
# mono initialize.sh copies the file when the value matches /*|~*.
case "$got" in
    /*|\~*) fail "other linux: signingkey is a path mono would copy" ;;
    *) pass "other linux: no path for mono's initialize.sh to copy" ;;
esac

echo
[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failure(s)" >&2; exit 1; }
