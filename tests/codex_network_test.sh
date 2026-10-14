#!/usr/bin/env bash
# Regression test: on serveserve, Codex's workspace-write sandbox has network
# access, so bean refresh works in Codex without an approval prompt.
#
# The Codex config modifier sets sandbox_workspace_write.network_access to true
# on serveserve, where it is or at the end of the table, and on rollback
# removes it where it still holds true. Other machines' values are left as
# they are.
# Renders the modifier into a throwaway directory; nothing touches the real home.
#
# Usage: tests/codex_network_test.sh
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
# with each TOGGLE (manage, bean, net) set to false.
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
render true net > "$WORK/rollback.sh"
render true bean > "$WORK/no-bean.sh"
render true bean net > "$WORK/neither.sh"
render true manage bean net > "$WORK/rolled-back.sh"

# json FILE: the TOML as JSON, leaving out the Cloudflare MCP entries and the
# agent environment, which the modifier also manages.
json() {
    uv run --no-project python -I -c 'import json, sys, tomllib; print(json.dumps(tomllib.load(sys.stdin.buffer)))' < "$1" |
        jq -cS 'del(.mcp_servers, .shell_environment_policy)'
}
# with_bean: JSON with Bean's paths appended where missing (tests/codex_bean_roots_test.sh).
with_bean() {
    jq -cS --arg d "$DATA" --arg c "$CONF" \
        '.sandbox_workspace_write.writable_roots = ((.sandbox_workspace_write.writable_roots // []) as $r | $r + ([$d, $c] - $r))'
}
net() { jq -cS ".sandbox_workspace_write.network_access = $1"; }
nonet() { jq -cS 'del(.sandbox_workspace_write.network_access)'; }

# Live configs Codex can load, in each spelling of network_access the modifier edits.
mkdir -p "$WORK/live"
cat > "$WORK/live/table-true.toml" <<TOML
model = "kept"

[sandbox_workspace_write]
writable_roots = ["/a", "$DATA", "$CONF"]
network_access = true

[tui]
x = 1
TOML
cat > "$WORK/live/table-false.toml" <<'TOML'
[sandbox_workspace_write]
"network_access" = false  # mine
writable_roots = ["/a"]
TOML
cat > "$WORK/live/table-without.toml" <<'TOML'
[sandbox_workspace_write]
writable_roots = ["/a"]

# The UI.
[tui]
x = 1
TOML
cat > "$WORK/live/dotted-false.toml" <<'TOML'
model = "kept"
sandbox_workspace_write . 'network_access' = false
TOML
cat > "$WORK/live/dotted-without.toml" <<'TOML'
model = "kept"
sandbox_workspace_write.writable_roots = ["/a"]

# The UI.
[tui]
x = 1
TOML
# A comment after the value is text, whatever it says.
printf '[sandbox_workspace_write]\nnetwork_access = false # previously = true\n' > "$WORK/live/comment-false.toml"
printf 'sandbox_workspace_write.network_access = true # previously = false\n' > "$WORK/live/comment-true.toml"
# CRLF after the value (the last line ending is LF: $(cat) drops a final CR).
printf 'sandbox_workspace_write.network_access = false\r\n[tui]\nx = 1\n' > "$WORK/live/crlf-false.toml"
printf '[sandbox_workspace_write]\nnetwork_access = true\r\n[tui]\nx = 1\n' > "$WORK/live/crlf-true.toml"
printf 'model = "kept"\n' > "$WORK/live/none.toml"
: > "$WORK/live/empty.toml"
# The key inside a multi-line string is text; a line in an array that starts with "[" opens an element.
cat > "$WORK/live/in-string.toml" <<'TOML'
developer_instructions = """
[sandbox_workspace_write]
network_access = false
"""
[sandbox_workspace_write]
x = [
  [1],
]
TOML
for live in "$WORK"/live/*.toml; do
    name=$(basename "$live" .toml)
    json "$live" >/dev/null || { fail "fixture $name is not valid TOML"; continue; }
    sh "$WORK/server.sh" < "$live" > "$WORK/server-$name.toml" 2>"$WORK/err" && rc=0 || rc=$?
    [ "$rc" -eq 0 ] || { fail "$name, serveserve: exit $rc: $(cat "$WORK/err")"; continue; }
    if ! got=$(json "$WORK/server-$name.toml" 2>/dev/null); then fail "$name, serveserve: output is not valid TOML"; continue; fi
    want=$(json "$live" | with_bean | net true)
    [ "$got" = "$want" ] && pass "$name, serveserve: network_access is true, nothing else changes" \
        || fail "$name, serveserve: got $got, want $want"
    sh "$WORK/server.sh" < "$WORK/server-$name.toml" > "$WORK/again.toml" 2>/dev/null
    cmp -s "$WORK/server-$name.toml" "$WORK/again.toml" && pass "$name, serveserve: applying again changes nothing" \
        || fail "$name, serveserve: applying again changes it"
    sh "$WORK/rollback.sh" < "$WORK/server-$name.toml" > "$WORK/undone.toml" 2>"$WORK/err" && rc=0 || rc=$?
    [ "$rc" -eq 0 ] && [ "$(json "$WORK/undone.toml")" = "$(json "$live" | with_bean | nonet)" ] \
        && pass "$name, rollback: network_access removed, the rest stays" \
        || fail "$name, rollback: rc=$rc, got $(json "$WORK/undone.toml" 2>&1), want $(json "$live" | with_bean | nonet)"
    # Straight from the live config, rollback removes only a true.
    sh "$WORK/rollback.sh" < "$live" > "$WORK/undone.toml" 2>"$WORK/err" && rc=0 || rc=$?
    case "$(json "$live" | jq -c .sandbox_workspace_write.network_access)" in
        true) want=$(json "$live" | with_bean | nonet) ;;
        *) want=$(json "$live" | with_bean) ;;
    esac
    [ "$rc" -eq 0 ] && [ "$(json "$WORK/undone.toml")" = "$want" ] \
        && pass "$name, rollback from live: only a true is removed" || fail "$name, rollback from live: rc=$rc, got $(json "$WORK/undone.toml" 2>&1), want $want"
    for from in "$live" "$WORK/server-$name.toml"; do
        sh "$WORK/elsewhere.sh" < "$from" > "$WORK/out.toml" 2>"$WORK/err" && rc=0 || rc=$?
        [ "$rc" -eq 0 ] && [ "$(json "$WORK/out.toml")" = "$(json "$from")" ] \
            && pass "$name, elsewhere ($(basename "$from")): network_access left as it is" || fail "$name, elsewhere: rc=$rc $(cat "$WORK/err")"
    done
done
check "table-true, serveserve: nothing to change, byte for byte" \
    'head -n 8 "$WORK/server-table-true.toml" | cmp -s - "$WORK/live/table-true.toml"'
check "table-false, serveserve: the live line becomes true, its comment kept" \
    "grep -qxF '\"network_access\" = true  # mine' \"\$WORK/server-table-false.toml\""
check "comment-false, serveserve: only the value changes, not the comment" \
    "grep -qxF 'network_access = true # previously = true' \"\$WORK/server-comment-false.toml\""
check "comment-true, serveserve: nothing to change, byte for byte" \
    'head -n 1 "$WORK/server-comment-true.toml" | cmp -s - "$WORK/live/comment-true.toml"'
check "crlf-false, serveserve: the value changes, the CR stays" \
    "head -n 1 \"\$WORK/server-crlf-false.toml\" | cmp -s - <(printf 'sandbox_workspace_write.network_access = true\\r\\n')"
check "table-without, serveserve: the key goes at the end of its table, before the blank line" \
    "[ \"\$(sed -n 2,4p \"\$WORK/server-table-without.toml\")\" = \"\$(printf 'writable_roots = [\"/a\", \"%s\", \"%s\"]\\nnetwork_access = true\\n' \"\$DATA\" \"\$CONF\")\" ]"
check "dotted-false, serveserve: the dotted key becomes true in place" \
    "grep -qxF \"sandbox_workspace_write . 'network_access' = true\" \"\$WORK/server-dotted-false.toml\""
check "dotted-without, serveserve: a dotted key goes after the others, before the comment" \
    "[ \"\$(sed -n 3p \"\$WORK/server-dotted-without.toml\")\" = 'sandbox_workspace_write.network_access = true' ]"
check "none, serveserve: a new table holds both keys" \
    "grep -A2 -xF '[sandbox_workspace_write]' \"\$WORK/server-none.toml\" | tail -n 1 | grep -qxF 'network_access = true'"
check "in-string, serveserve: the multi-line string is untouched" \
    "head -n 4 \"\$WORK/server-in-string.toml\" | cmp -s - <(head -n 4 \"\$WORK/live/in-string.toml\")"

# The live config on serveserve, as applied before this change, already holds
# Bean's roots and the rest: the only change is one added line.
printf 'model = "kept"\n\n[sandbox_workspace_write]\nwritable_roots = ["/plugins"]\n\n[tui]\nx = 1\n' |
    sh "$WORK/rollback.sh" > "$WORK/live-shape.toml"
sh "$WORK/server.sh" < "$WORK/live-shape.toml" > "$WORK/out.toml"
check "live shape, serveserve: the only difference is the network line" \
    '[ "$(diff "$WORK/live-shape.toml" "$WORK/out.toml" | grep "^[<>]")" = "> network_access = true" ]'

# Forms the modifier does not edit fail the apply on serveserve, with the
# reason and nothing printed; elsewhere they pass unchanged.
mkdir -p "$WORK/other"
printf '[sandbox_workspace_write]\nnetwork_access = "true"\n' > "$WORK/other/string.toml"
printf '[sandbox_workspace_write]\nnetwork_access = [\n  true]\n' > "$WORK/other/array.toml"
for live in "$WORK"/other/*.toml; do
    name=$(basename "$live" .toml)
    json "$live" >/dev/null || { fail "fixture $name is not valid TOML"; continue; }
    for script in server rollback; do
        sh "$WORK/$script.sh" < "$live" > "$WORK/out.toml" 2>"$WORK/err" && rc=0 || rc=$?
        [ "$rc" -ne 0 ] && grep -q "network_access is in a form this script does not edit" "$WORK/err" && [ ! -s "$WORK/out.toml" ] \
            && pass "$name, $script: a value it does not edit fails the apply, with the reason" \
            || fail "$name, $script: rc=$rc $(cat "$WORK/err")"
    done
    sh "$WORK/elsewhere.sh" < "$live" > "$WORK/out.toml" 2>"$WORK/err" && rc=0 || rc=$?
    [ "$rc" -eq 0 ] && [ "$(json "$WORK/out.toml")" = "$(json "$live")" ] \
        && pass "$name, elsewhere: passes unchanged" || fail "$name, elsewhere: rc=$rc $(cat "$WORK/err")"
done
# With Bean's roots rolled back, a table it does not edit fails for the network key.
printf 'sandbox_workspace_write = { network_access = false }\n' > "$WORK/inline.toml"
sh "$WORK/no-bean.sh" < "$WORK/inline.toml" > "$WORK/out.toml" 2>"$WORK/err" && rc=0 || rc=$?
check "inline table, serveserve without Bean: fails the apply, with the reason" \
    '[ "$rc" -ne 0 ] && grep -q "network_access is in a form this script does not edit" "$WORK/err" && [ ! -s "$WORK/out.toml" ]'
# Rolling back both, an inline table is left as it is where it does not hold
# true; where it does, the check fails the apply rather than leave it.
sh "$WORK/neither.sh" < "$WORK/inline.toml" > "$WORK/out.toml" 2>"$WORK/err" && rc=0 || rc=$?
check "inline table false, Bean and network rolled back: passes unchanged" \
    '[ "$rc" -eq 0 ] && [ "$(json "$WORK/out.toml")" = "$(json "$WORK/inline.toml")" ]'
printf 'sandbox_workspace_write = { network_access = true }\n' > "$WORK/inline-true.toml"
sh "$WORK/neither.sh" < "$WORK/inline-true.toml" > "$WORK/out.toml" 2>"$WORK/err" && rc=0 || rc=$?
check "inline table true, Bean and network rolled back: fails the apply rather than leave it" \
    '[ "$rc" -ne 0 ] && grep -q "expected network_access" "$WORK/err" && [ ! -s "$WORK/out.toml" ]'
# A writable_roots the scanner does not edit is Bean's concern: with Bean
# rolled back and nothing to remove, the network key is still set.
printf '[sandbox_workspace_write]\nwritable_roots = ["/t\\u006dp"]\nnetwork_access = false\n' > "$WORK/escaped-roots.toml"
sh "$WORK/no-bean.sh" < "$WORK/escaped-roots.toml" > "$WORK/out.toml" 2>"$WORK/err" && rc=0 || rc=$?
check "escaped roots, serveserve without Bean: network_access set, roots left as they are" \
    '[ "$rc" -eq 0 ] && [ "$(json "$WORK/out.toml")" = "$(json "$WORK/escaped-roots.toml" | net true)" ]'

# The toggles are separate: rolling back the network leaves Bean's roots and
# the agent identity, and rolling back Bean leaves the network.
sh "$WORK/server.sh" < "$WORK/live/table-without.toml" > "$WORK/all.toml"
sh "$WORK/rollback.sh" < "$WORK/all.toml" > "$WORK/out.toml"
check "network rolled back: Bean's roots and the agent environment stay" \
    '[ "$(json "$WORK/out.toml")" = "$(json "$WORK/all.toml" | nonet)" ] && grep -q "^GH_CONFIG_DIR = " "$WORK/out.toml"'
sh "$WORK/no-bean.sh" < "$WORK/all.toml" > "$WORK/out.toml"
check "Bean rolled back: the network stays" \
    '[ "$(json "$WORK/out.toml" | jq -c .sandbox_workspace_write)" = "{\"network_access\":true,\"writable_roots\":[\"/a\"]}" ]'

# Without uv nothing checks the result: on serveserve, with every toggle
# rolled back, the apply fails.
mkdir -p "$WORK/nouv"
ln -s "$(command -v awk)" "$WORK/nouv/awk"; ln -s "$(command -v cat)" "$WORK/nouv/cat"
HOME="$WORK/nouv" PATH="$WORK/nouv" /bin/sh "$WORK/rolled-back.sh" < "$WORK/all.toml" > "$WORK/out.toml" 2>"$WORK/err" && rc=0 || rc=$?
check "serveserve, all rolled back, no uv: the apply fails rather than go unchecked" \
    '[ "$rc" -ne 0 ] && grep -q "uv not found to check" "$WORK/err" && [ ! -s "$WORK/out.toml" ]'

echo
[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failure(s)" >&2; exit 1; }
