#!/usr/bin/env bash
# Regression test: fish puts ~/.local/bin (uv, chezmoi, passh) on PATH by
# itself, without relying on uv's installer having written env.fish.
#
# Renders config.fish for each OS into a throwaway HOME and sources it in a
# fish that starts without ~/.local/bin on PATH. Nothing touches the real home.
#
# Usage: tests/fish_path_test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Resolved before PATH is cleared below: Homebrew's fish is not in /usr/bin.
FISH="$(command -v fish)"

failures=0
for os in linux darwin; do
    home="$WORK/$os"
    mkdir -p "$home/.local/bin" "$home/.config"
    chezmoi execute-template --file "$REPO_DIR/dot_config/fish/config.fish.tmpl" \
        --source "$REPO_DIR" \
        --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" \
        | grep -v "brew shellenv" > "$WORK/config-$os.fish"  # brew is Mac-only; not under test

    if env -i HOME="$home" XDG_CONFIG_HOME="$home/.config" PATH=/usr/bin:/bin \
        "$FISH" --no-config -c "source $WORK/config-$os.fish; contains -- $home/.local/bin \$PATH"; then
        printf 'ok:   %s: ~/.local/bin on PATH\n' "$os"
    else
        printf 'FAIL: %s: ~/.local/bin not on PATH\n' "$os" >&2
        failures=$((failures + 1))
    fi
done

[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failure(s)" >&2; exit 1; }
