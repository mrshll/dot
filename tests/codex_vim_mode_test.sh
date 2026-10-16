#!/usr/bin/env bash
# Regression test: Codex starts its composer in Vim normal mode on every machine.
#
# The Codex config modifier sets tui.vim_mode_default to true where it is, at
# the end of the [tui] table where it is not, or in a new [tui] table, and
# fails the apply on a form it does not edit.
# Renders the modifier into a throwaway directory; nothing touches the real home.
#
# Usage: tests/codex_vim_mode_test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
TEMPLATE=dot_codex/modify_private_config.toml.tmpl

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
pass() { printf 'ok:   %s\n' "$*"; }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

# render IS_SERVER: the modifier as chezmoi renders it on Linux.
render() {
    printf '[data]\n  hostname = "test"\n  os = "linux"\n  is_server = %s\n  has_op = false\n' "$1" > "$WORK/chezmoi.toml"
    chezmoi execute-template --file "$REPO_DIR/$TEMPLATE" --source "$REPO_DIR" --config "$WORK/chezmoi.toml" \
        --override-data '{"chezmoi":{"os":"linux"}}'
}
render true > "$WORK/server.sh"
render false > "$WORK/elsewhere.sh"

# json FILE: the TOML as JSON, leaving out what the other toggles manage.
json() {
    uv run --no-project python -I -c 'import json, sys, tomllib; print(json.dumps(tomllib.load(sys.stdin.buffer)))' < "$1" |
        jq -cS 'del(.mcp_servers, .shell_environment_policy, .sandbox_workspace_write)'
}
vim() { jq -cS '.tui.vim_mode_default = true'; }

# Live configs Codex can load, in each spelling of [tui] the modifier edits.
mkdir -p "$WORK/live"
printf '[tui]\nvim_mode_default = true\n' > "$WORK/live/table-true.toml"
printf '[tui]\n"vim_mode_default" = false  # mine\nx = 1\n' > "$WORK/live/table-false.toml"
printf 'model = "kept"\n\n[tui]\nx = 1\n\n# Next.\n[other]\ny = 2\n' > "$WORK/live/table-without.toml"
printf '[other]\ny = 2\n\n[tui]\nx = 1\n' > "$WORK/live/table-last.toml"
printf '[tui]\nvim_mode_default = false\r\nx = 1\n' > "$WORK/live/crlf-false.toml"
printf '[tui.model_availability_nux]\n"gpt-x" = 4\n' > "$WORK/live/subtable-only.toml"
printf 'model = "kept"\n' > "$WORK/live/none.toml"
: > "$WORK/live/empty.toml"
# The table inside a multi-line string is text.
printf 'developer_instructions = """\n[tui]\nvim_mode_default = false\n"""\n' > "$WORK/live/in-string.toml"
for live in "$WORK"/live/*.toml; do
    name=$(basename "$live" .toml)
    json "$live" >/dev/null || { fail "fixture $name is not valid TOML"; continue; }
    for script in server elsewhere; do
        sh "$WORK/$script.sh" < "$live" > "$WORK/$script-$name.toml" 2>"$WORK/err" && rc=0 || rc=$?
        [ "$rc" -eq 0 ] || { fail "$name, $script: exit $rc: $(cat "$WORK/err")"; continue; }
        if ! got=$(json "$WORK/$script-$name.toml" 2>/dev/null); then fail "$name, $script: output is not valid TOML"; continue; fi
        want=$(json "$live" | vim)
        [ "$got" = "$want" ] && pass "$name, $script: vim_mode_default is true, nothing else changes" \
            || fail "$name, $script: got $got, want $want"
        sh "$WORK/$script.sh" < "$WORK/$script-$name.toml" > "$WORK/again.toml" 2>/dev/null
        cmp -s "$WORK/$script-$name.toml" "$WORK/again.toml" && pass "$name, $script: applying again changes nothing" \
            || fail "$name, $script: applying again changes it"
    done
done
check "table-true: nothing to change, byte for byte" \
    'head -n 2 "$WORK/elsewhere-table-true.toml" | cmp -s - "$WORK/live/table-true.toml"'
check "table-false: the live line becomes true, its comment kept" \
    "grep -qxF '\"vim_mode_default\" = true  # mine' \"\$WORK/elsewhere-table-false.toml\""
check "table-without: the key goes at the end of its table, before the blank line" \
    "[ \"\$(sed -n 4,6p \"\$WORK/elsewhere-table-without.toml\")\" = \"\$(printf 'x = 1\\nvim_mode_default = true\\n')\" ]"
check "table-last: the key goes at the end of the file's last table" \
    "[ \"\$(sed -n 5,6p \"\$WORK/elsewhere-table-last.toml\")\" = \"\$(printf 'x = 1\\nvim_mode_default = true')\" ]"
check "crlf-false: the value changes, the CR stays" \
    "sed -n 2p \"\$WORK/elsewhere-crlf-false.toml\" | cmp -s - <(printf 'vim_mode_default = true\\r\\n')"
check "none: a new [tui] table holds the key" \
    "grep -A1 -xF '[tui]' \"\$WORK/elsewhere-none.toml\" | tail -n 1 | grep -qxF 'vim_mode_default = true'"
check "in-string: the multi-line string is untouched" \
    "head -n 4 \"\$WORK/elsewhere-in-string.toml\" | cmp -s - \"\$WORK/live/in-string.toml\""

# The live config's shape: the only change is one added line.
printf 'model = "kept"\n\n[tui]\nscreen_reader_detection_done = true\n\n[tui.model_availability_nux]\n"gpt-x" = 4\n' > "$WORK/live-shape.toml"
sh "$WORK/elsewhere.sh" < "$WORK/live-shape.toml" > "$WORK/out.toml"
check "live shape: the only difference is the vim line" \
    '[ "$(diff "$WORK/live-shape.toml" "$WORK/out.toml" | grep "^[<>]" | grep -v "mcp\|url\|^> \$")" = "> vim_mode_default = true" ]'

# Forms the modifier does not edit fail the apply everywhere, with the reason
# and nothing printed.
mkdir -p "$WORK/other"
printf '[tui]\nvim_mode_default = "true"\n' > "$WORK/other/string.toml"
printf 'tui = { x = 1 }\n' > "$WORK/other/inline.toml"
printf 'tui.x = 1\n' > "$WORK/other/dotted.toml"
printf '["tui"]\nx = 1\n' > "$WORK/other/quoted.toml"
for live in "$WORK"/other/*.toml; do
    name=$(basename "$live" .toml)
    json "$live" >/dev/null || { fail "fixture $name is not valid TOML"; continue; }
    for script in server elsewhere; do
        sh "$WORK/$script.sh" < "$live" > "$WORK/out.toml" 2>"$WORK/err" && rc=0 || rc=$?
        [ "$rc" -ne 0 ] && grep -q "vim_mode_default is in a form this script does not edit" "$WORK/err" && [ ! -s "$WORK/out.toml" ] \
            && pass "$name, $script: a form it does not edit fails the apply, with the reason" \
            || fail "$name, $script: rc=$rc $(cat "$WORK/err")"
    done
done

echo
[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failure(s)" >&2; exit 1; }
