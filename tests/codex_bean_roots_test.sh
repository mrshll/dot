#!/usr/bin/env bash
# Regression test: on serveserve, Codex's workspace-write sandbox can write
# Bean's data and config, so bean runs in Codex without an approval prompt.
#
# The Codex config modifier appends both paths to
# sandbox_workspace_write.writable_roots after what the live list holds, in
# whichever spelling it uses, and removes them on rollback. Other machines'
# lists are left as they are.
# Renders the modifier into a throwaway directory; nothing touches the real home.
#
# Usage: tests/codex_bean_roots_test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
DATA="$HOME/.local/share/pond/bean"
CONF="$HOME/.config/pond/bean"
TEMPLATE=dot_codex/modify_private_config.toml.tmpl

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
pass() { printf 'ok:   %s\n' "$*"; }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

# render IS_SERVER [TOGGLE...]: the modifier as chezmoi renders it on Linux,
# with each TOGGLE (manage, bean) set to false.
render() {
    local tmpl="$REPO_DIR/$TEMPLATE" toggle
    cp "$tmpl" "$WORK/rollback.tmpl"
    for toggle in "${@:2}"; do
        sed -i "s/{{- \$$toggle := .is_server }}/{{- \$$toggle := false }}/" "$WORK/rollback.tmpl"
        grep -q "\$$toggle := false" "$WORK/rollback.tmpl" || { echo "no \$$toggle toggle in $TEMPLATE" >&2; return 1; }
    done
    tmpl="$WORK/rollback.tmpl"
    printf '[data]\n  hostname = "test"\n  os = "linux"\n  is_server = %s\n  has_op = false\n' "$1" > "$WORK/chezmoi.toml"
    chezmoi execute-template --file "$tmpl" --source "$REPO_DIR" --config "$WORK/chezmoi.toml" \
        --override-data '{"chezmoi":{"os":"linux"}}'
}
render true > "$WORK/server.sh"
render false > "$WORK/elsewhere.sh"
render true bean > "$WORK/rollback.sh"
render true manage > "$WORK/no-identity.sh"
render true manage bean > "$WORK/rolled-back.sh"

# json FILE: the TOML as JSON, leaving out what the modifier manages besides
# Bean's roots (Cloudflare MCP entries and the agent environment). An empty
# writable_roots, and then an empty table, count as none: removing Bean's
# paths from a list that held only them leaves "writable_roots = []".
json() {
    uv run --no-project python -I -c 'import json, sys, tomllib; print(json.dumps(tomllib.load(sys.stdin.buffer)))' < "$1" |
        jq -cS 'del(.mcp_servers, .shell_environment_policy)
            | if .sandbox_workspace_write.writable_roots == [] then del(.sandbox_workspace_write.writable_roots) else . end
            | if .sandbox_workspace_write == {} then del(.sandbox_workspace_write) else . end'
}
# with_bean / without_bean: JSON with Bean's paths appended where missing, or removed.
with_bean() {
    jq -cS --arg d "$DATA" --arg c "$CONF" \
        '.sandbox_workspace_write.writable_roots = ((.sandbox_workspace_write.writable_roots // []) as $r | $r + ([$d, $c] - $r))'
}
without_bean() {
    jq -cS --arg d "$DATA" --arg c "$CONF" \
        'if .sandbox_workspace_write.writable_roots then .sandbox_workspace_write.writable_roots -= [$d, $c] else . end'
}

# Live configs Codex can load, in each spelling of writable_roots the modifier edits.
mkdir -p "$WORK/live"
cat > "$WORK/live/table.toml" <<'TOML'
model = "kept"

[sandbox_workspace_write]
writable_roots = ["/a", '/b']
network_access = true

[tui]
screen_reader_detection_done = true
TOML
cat > "$WORK/live/multiline.toml" <<'TOML'
[sandbox_workspace_write]
"writable_roots" = [
    "/a",
    '/b',
]  # kept
TOML
cat > "$WORK/live/dotted.toml" <<'TOML'
model = "kept"
sandbox_workspace_write.writable_roots = ["/a"]

[tui]
x = 1
TOML
cat > "$WORK/live/dotted-multiline.toml" <<'TOML'
sandbox_workspace_write . 'writable_roots' = [
  "/a"
]
sandbox_workspace_write.network_access = true
TOML
cat > "$WORK/live/dotted-without.toml" <<'TOML'
model = "kept"
sandbox_workspace_write.network_access = true

# The UI.
[tui]
x = 1
TOML
cat > "$WORK/live/table-without.toml" <<'TOML'
[sandbox_workspace_write]
network_access = true

[tui]
x = 1
TOML
printf 'model = "kept"\n' > "$WORK/live/none.toml"
: > "$WORK/live/empty.toml"
printf '[sandbox_workspace_write]\nwritable_roots = []\n' > "$WORK/live/empty-array.toml"
# Brackets, commas and hashes inside strings are text; duplicates and order stay.
cat > "$WORK/live/punctuation.toml" <<'TOML'
[sandbox_workspace_write]
writable_roots = ["/a]b", '/c#d', "/e,f", "/a]b"] # end
TOML
# A table header or the key inside a multi-line string is text.
cat > "$WORK/live/in-string.toml" <<'TOML'
developer_instructions = """
[sandbox_workspace_write]
writable_roots = ["/example"]
"""
model = "kept"
TOML
# A line in an array that starts with "[" opens an element, not a table.
printf 'x = [\n  [1],\n]\nsandbox_workspace_write.writable_roots = ["/a"]\n' > "$WORK/live/nested-top.toml"
printf '[sandbox_workspace_write]\nx = [\n  [1],\n]\nwritable_roots = ["/a"]\n' > "$WORK/live/nested-table.toml"
# One of Bean's paths is there already: only the other is appended.
printf '[sandbox_workspace_write]\nwritable_roots = ["/a", "%s"]\n' "$CONF" > "$WORK/live/one.toml"
# Both are there, with a comment inside: nothing to edit, so it stays as it is.
printf '[sandbox_workspace_write]\nwritable_roots = [\n  "%s", # data\n  "%s",\n  "/a",\n]\n' "$DATA" "$CONF" > "$WORK/live/both-commented.toml"
for live in "$WORK"/live/*.toml; do
    name=$(basename "$live" .toml)
    json "$live" >/dev/null || { fail "fixture $name is not valid TOML"; continue; }
    sh "$WORK/server.sh" < "$live" > "$WORK/server-$name.toml" 2>"$WORK/err" && rc=0 || rc=$?
    [ "$rc" -eq 0 ] || { fail "$name, serveserve: exit $rc: $(cat "$WORK/err")"; continue; }
    if ! got=$(json "$WORK/server-$name.toml" 2>/dev/null); then fail "$name, serveserve: output is not valid TOML"; continue; fi
    want=$(json "$live" | with_bean)
    [ "$got" = "$want" ] && pass "$name, serveserve: Bean's paths appended after the live roots, nothing else changes" \
        || fail "$name, serveserve: got $got, want $want"
    sh "$WORK/server.sh" < "$WORK/server-$name.toml" > "$WORK/again.toml" 2>/dev/null
    cmp -s "$WORK/server-$name.toml" "$WORK/again.toml" && pass "$name, serveserve: applying again changes nothing" \
        || fail "$name, serveserve: applying again changes it"
    sh "$WORK/rollback.sh" < "$WORK/server-$name.toml" > "$WORK/undone.toml" 2>"$WORK/err" && rc=0 || rc=$?
    if [ "$name" = both-commented ]; then
        # Bean's paths sit in an array with a comment: removing them would drop it.
        [ "$rc" -ne 0 ] && grep -q "form this script does not edit" "$WORK/err" && [ ! -s "$WORK/undone.toml" ] \
            && pass "$name, rollback: removing them from a commented array fails the apply, with the reason" \
            || fail "$name, rollback: rc=$rc for a commented array"
    else
        [ "$rc" -eq 0 ] && [ "$(json "$WORK/undone.toml")" = "$(json "$live" | without_bean)" ] \
            && pass "$name, rollback: Bean's paths removed, the rest of the roots stay in order" \
            || fail "$name, rollback: rc=$rc, got $(json "$WORK/undone.toml" 2>&1), want $(json "$live" | without_bean)"
    fi
    sh "$WORK/elsewhere.sh" < "$WORK/server-$name.toml" > "$WORK/undone.toml" 2>"$WORK/err" && rc=0 || rc=$?
    [ "$rc" -eq 0 ] && [ "$(json "$WORK/undone.toml")" = "$got" ] \
        && pass "$name, elsewhere: the roots are left as they are" || fail "$name, elsewhere: rc=$rc $(cat "$WORK/err")"
done
check "both-commented, serveserve: the array is left byte for byte" \
    'head -n 6 "$WORK/server-both-commented.toml" | cmp -s - "$WORK/live/both-commented.toml"'
check "table, serveserve: the live line gets the paths, in place" \
    "grep -qxF 'writable_roots = [\"/a\", '\''/b'\'', \"$DATA\", \"$CONF\"]' \"\$WORK/server-table.toml\""
check "table-without, serveserve: the key goes at the end of its table, before the blank line" \
    "[ \"\$(sed -n 2,3p \"\$WORK/server-table-without.toml\")\" = \"\$(printf 'network_access = true\\nwritable_roots = [\"%s\", \"%s\"]' \"\$DATA\" \"\$CONF\")\" ]"
check "dotted-without, serveserve: a dotted key goes after the others, before the comment" \
    "[ \"\$(sed -n 3p \"\$WORK/server-dotted-without.toml\")\" = \"sandbox_workspace_write.writable_roots = [\\\"\$DATA\\\", \\\"\$CONF\\\"]\" ]"
check "in-string, serveserve: the multi-line string is untouched" \
    "head -n 4 \"\$WORK/server-in-string.toml\" | cmp -s - <(head -n 4 \"\$WORK/live/in-string.toml\")"

# Forms the modifier does not edit fail the apply on serveserve, with the
# reason and nothing printed; elsewhere, with no Bean path to remove, they pass.
mkdir -p "$WORK/other"
printf '[sandbox_workspace_write]\nwritable_roots = [\n  "/a", # mine\n]\n' > "$WORK/other/comment.toml"
printf '[sandbox_workspace_write]\nwritable_roots = ["/a\\\\b"]\n' > "$WORK/other/escape.toml"
printf '[sandbox_workspace_write]\nwritable_roots = ["""/a"""]\n' > "$WORK/other/multiline-string.toml"
printf '[sandbox_workspace_write]\nwritable_roots = [1]\n' > "$WORK/other/number.toml"
printf 'sandbox_workspace_write = { writable_roots = ["/a"] }\n' > "$WORK/other/inline-table.toml"
printf '["sandbox_workspace_write"]\nwritable_roots = ["/a"]\n' > "$WORK/other/quoted-header.toml"
printf '[sandbox_workspace_write.extra]\nx = 1\n' > "$WORK/other/subtable.toml"
for live in "$WORK"/other/*.toml; do
    name=$(basename "$live" .toml)
    json "$live" >/dev/null || { fail "fixture $name is not valid TOML"; continue; }
    sh "$WORK/server.sh" < "$live" > "$WORK/out.toml" 2>"$WORK/err" && rc=0 || rc=$?
    [ "$rc" -ne 0 ] && grep -q "writable_roots is in a form this script does not edit" "$WORK/err" && [ ! -s "$WORK/out.toml" ] \
        && pass "$name, serveserve: a form it does not edit fails the apply, with the reason" \
        || fail "$name, serveserve: rc=$rc for a form it does not edit"
    sh "$WORK/elsewhere.sh" < "$live" > "$WORK/out.toml" 2>"$WORK/err" && rc=0 || rc=$?
    [ "$rc" -eq 0 ] && [ "$(json "$WORK/out.toml")" = "$(json "$live")" ] \
        && pass "$name, elsewhere: passes unchanged" || fail "$name, elsewhere: rc=$rc $(cat "$WORK/err")"
done

# The two toggles are separate: rolling back Bean leaves the agent identity,
# and rolling back the identity leaves Bean.
sh "$WORK/server.sh" < "$WORK/live/table.toml" > "$WORK/both.toml"
sh "$WORK/rollback.sh" < "$WORK/both.toml" > "$WORK/out.toml"
check "bean rolled back: the agent environment stays" \
    'uv run --no-project python -I -c "import sys, tomllib; c = tomllib.load(open(sys.argv[1], \"rb\")); sys.exit(c[\"shell_environment_policy\"][\"set\"][\"GH_CONFIG_DIR\"] != sys.argv[2])" "$WORK/out.toml" "$HOME/.config/gh-agent"'
sh "$WORK/no-identity.sh" < "$WORK/both.toml" > "$WORK/out.toml"
check "identity rolled back: Bean's roots stay" '[ "$(json "$WORK/out.toml")" = "$(json "$WORK/both.toml")" ]'

# Without uv nothing checks the result: on serveserve, with both toggles
# rolled back, the apply fails; elsewhere the result is still emitted, and
# writable_roots, in whatever form, is left as it is.
mkdir -p "$WORK/nouv"
ln -s "$(command -v awk)" "$WORK/nouv/awk"; ln -s "$(command -v cat)" "$WORK/nouv/cat"
nouv() { HOME="$WORK/nouv" PATH="$WORK/nouv" /bin/sh "$@"; }
printf '["sandbox_workspace_write"]\nwritable_roots = ["%s"]\n' "$DATA" > "$WORK/quoted-bean.toml"
printf '[sandbox_workspace_write]\nwritable_roots = ["%s"]\n' "${DATA%bean}\\u0062ean" > "$WORK/escaped-bean.toml"
for live in "$WORK/quoted-bean.toml" "$WORK/escaped-bean.toml" "$WORK/server-table.toml"; do
    nouv "$WORK/elsewhere.sh" < "$live" > "$WORK/out.toml" 2>"$WORK/err" && rc=0 || rc=$?
    check "elsewhere, no uv ($(basename "$live" .toml)): writable_roots left as it is" \
        '[ "$rc" -eq 0 ] && [ "$(json "$WORK/out.toml")" = "$(json "$live")" ]'
done
# A multi-line string may end in four or five quotes: the scanner must not
# take the extra ones for a string that hides the rest of the line, or it
# loses track of arrays and tables (and the Cloudflare entries get doubled).
for q in '"' "'"; do
    printf '[mcp_servers.other]\nargs = [%s%s%sx %s%s%s%s]\nkeep = [%s%s%s\nx%s%s%s%s%s]\n[mcp_servers.cloudflare]\nurl = "https://old.example"\n' \
        "$q" "$q" "$q" "$q" "$q" "$q" "$q" "$q" "$q" "$q" "$q" "$q" "$q" "$q" "$q" > "$WORK/quotes.toml"
    nouv "$WORK/elsewhere.sh" < "$WORK/quotes.toml" > "$WORK/out.toml" 2>"$WORK/err" && rc=0 || rc=$?
    check "elsewhere, no uv: a multi-line string ending in extra quotes ($q) keeps the scanner on track" \
        '[ "$rc" -eq 0 ] && [ "$(json "$WORK/out.toml")" = "$(json "$WORK/quotes.toml")" ] && [ "$(grep -c "^\[mcp_servers.cloudflare\]" "$WORK/out.toml")" = 1 ]'
done
nouv "$WORK/rolled-back.sh" < "$WORK/server-table.toml" > "$WORK/out.toml" 2>"$WORK/err" && rc=0 || rc=$?
check "serveserve, both rolled back, no uv: the apply fails rather than go unchecked" \
    '[ "$rc" -ne 0 ] && grep -q "uv not found to check" "$WORK/err" && [ ! -s "$WORK/out.toml" ]'
sh "$WORK/rolled-back.sh" < "$WORK/server-table.toml" > "$WORK/out.toml"
check "serveserve, both rolled back: Bean's paths come out" '[ "$(json "$WORK/out.toml")" = "$(json "$WORK/live/table.toml")" ]'

echo
[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failure(s)" >&2; exit 1; }
