# Sets the keys in $settings ("section/key=value" lines) in the Deskflow.conf
# on stdin and passes every other line through. The Deskflow GUI rewrites this
# file itself (computer name, last version, anything changed in its settings
# dialog), so only these keys are owned here. Quit Deskflow before applying:
# a running GUI may write its own values back over these.
awk -v settings="$settings" '
BEGIN {
    n = split(settings, lines, "\n")
    for (i = 1; i <= n; i++) {
        if (lines[i] == "") continue
        slash = index(lines[i], "/"); eq = index(lines[i], "=")
        sec = substr(lines[i], 1, slash - 1)
        key = substr(lines[i], slash + 1, eq - slash - 1)
        if (!(sec in nkeys)) order[++nsec] = sec
        keys[sec, ++nkeys[sec]] = key
        want[sec, key] = substr(lines[i], eq + 1)
    }
}
# Owned keys still missing from section sec, written at its end.
function finish(sec,    i, k) {
    if (!(sec in nkeys)) return
    for (i = 1; i <= nkeys[sec]; i++) {
        k = keys[sec, i]
        if (!((sec, k) in done)) print k "=" want[sec, k]
        done[sec, k] = 1
    }
    seen[sec] = 1
}
# Blank lines are held back so a key added at the end of a section lands
# before the blank line that separates it from the next one.
function blanks() { for (; held > 0; held--) print "" }
{ sub(/\r$/, "") }
/^[ \t]*$/ { held++; next }
/^[ \t]*\[.*\][ \t]*$/ {
    finish(cur)
    blanks()
    print
    cur = $0; gsub(/^[ \t]*\[|\][ \t]*$/, "", cur)
    next
}
{
    k = $0; sub(/[ \t]*=.*$/, "", k); sub(/^[ \t]+/, "", k)
    if (index($0, "=") && ((cur, k) in want)) {
        # Keep the first copy of an owned key, with our value; drop repeats.
        if (!((cur, k) in done)) { blanks(); print k "=" want[cur, k] }
        done[cur, k] = 1
        next
    }
    blanks()
    print
}
END {
    finish(cur)
    blanks()
    for (s = 1; s <= nsec; s++) {
        if (order[s] in seen) continue
        if (NR > 0 || s > 1) print ""
        print "[" order[s] "]"
        finish(order[s])
    }
}'
