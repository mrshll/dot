#!/usr/bin/env bash
# Regression test for the Mac's marshbox-screen fish function: one SSH tunnel
# (127.0.0.1:15900 -> marshbox 127.0.0.1:5900) reused across invocations, then
# Apple Screen Sharing on it.
#
# Runs the function against stub ssh/nc/open that record their arguments;
# nothing connects anywhere and nothing is launched.
#
# Usage: tests/marshbox_screen_test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FUNC="$REPO_DIR/dot_config/fish/functions/marshbox-screen.fish"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FISH="$(command -v fish)"

stubs="$WORK/bin"
mkdir -p "$stubs"
# ssh: -O check answers from the fake master; -M starts it (and its socket and
# listener) unless told to fail; -O exit stops it.
cat > "$stubs/ssh" <<'EOF'
#!/bin/sh
echo "ssh $*" >> "$STATE/log"
ctl=""; prev=""
for a in "$@"; do [ "$prev" = "-S" ] && ctl=$a; prev=$a; done
case " $* " in
    *" -O check "*) [ -e "$STATE/master" ] && [ -S "$ctl" -o -e "$ctl" ] ;;
    *" -O exit "*) [ -e "$STATE/exit_fail" ] && exit 255; rm -f "$STATE/master" "$STATE/listening" "$ctl" ;;
    *" -M "*)
        [ -e "$STATE/fail_start" ] && exit 255
        [ -e "$STATE/slow_start" ] && sleep 1.5
        touch "$STATE/master" "$STATE/listening" "$ctl" ;;
    *"ss -Hltn"*) [ -e "$STATE/server" ] && echo "LISTEN 0 5 127.0.0.1:5900 0.0.0.0:*"; exit 0 ;;
    *) exit 1 ;;
esac
EOF
# nc: only the -z port check is expected; anything else would be a connection
# to the VNC port, which TigerVNC counts towards blacklisting.
cat > "$stubs/nc" <<'EOF'
#!/bin/sh
echo "nc $*" >> "$STATE/log"
case " $* " in
    *" -z "*) [ -e "$STATE/listening" ] || [ -e "$STATE/busy" ] ;;
    *) echo "nc-probe" >> "$STATE/../probes" ;;  # kept across resets
esac
EOF
cat > "$stubs/open" <<'EOF'
#!/bin/sh
echo "open $*" >> "$STATE/log"
[ ! -e "$STATE/open_fail" ]
EOF
chmod +x "$stubs"/*

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
pass() { printf 'ok:   %s\n' "$*"; }

# run ARGS...: call the function in a clean fish; prints its exit status.
run() {
    env -i HOME="$WORK/home" STATE="$WORK/state" PATH="$stubs:/usr/bin:/bin" \
        "$FISH" --no-config -c "source $FUNC; marshbox-screen $*" \
        > "$WORK/out" 2>&1 && echo 0 || echo $?
}
reset() { rm -rf "$WORK/state" "$WORK/home"; mkdir -p "$WORK/state" "$WORK/home/.ssh"; : > "$WORK/state/log"; touch "$WORK/state/server"; }
starts() { grep -c ' -M ' "$WORK/state/log" || true; }
opens() { grep -c '^open ' "$WORK/state/log" || true; }

# --- first run: start the tunnel, then open Screen Sharing on it -------------
reset
rc=$(run)
start=$(grep ' -M ' "$WORK/state/log" || true)
[ "$rc" = 0 ] && pass "first run succeeds" || fail "first run exit $rc: $(cat "$WORK/out")"
for want in "-F /dev/null" "-o IdentitiesOnly=yes" "-o IdentityAgent=none" \
    "-i $WORK/home/.ssh/id_ed25519_marshbox" "-o StrictHostKeyChecking=yes" \
    "-o ExitOnForwardFailure=yes" "-f -N -T" \
    "-L 127.0.0.1:15900:127.0.0.1:5900" "marsh@marshbox.local"; do
    grep -qF -- "$want" <<< "$start" && pass "tunnel uses '$want'" || fail "tunnel lacks '$want': $start"
done
grep -qiE 'pass(word|wd)' "$WORK/state/log" && fail "a password appears in some argument" \
    || pass "no password in any argument"
[ "$(grep '^open ' "$WORK/state/log")" = 'open -a Screen Sharing vnc://127.0.0.1:15900' ] \
    && pass "opens Screen Sharing on vnc://127.0.0.1:15900" || fail "open: $(grep '^open ' "$WORK/state/log")"
m_line=$(grep -n -- " -M " "$WORK/state/log" | head -n1 | cut -d: -f1)
o_line=$(grep -n "^open " "$WORK/state/log" | head -n1 | cut -d: -f1)
[ -n "$m_line" ] && [ -n "$o_line" ] && [ "$m_line" -lt "$o_line" ] \
    && pass "tunnel is up before Screen Sharing opens" || fail "tunnel start (line $m_line) not before open (line $o_line)"

# --- second run: reuse the tunnel ------------------------------------------
rc=$(run)
[ "$rc" = 0 ] && [ "$(starts)" = 1 ] && [ "$(opens)" = 2 ] \
    && pass "second run reuses the tunnel and opens again" \
    || fail "second run: exit $rc, starts $(starts), opens $(opens)"

# --- stop -------------------------------------------------------------------
rc=$(run stop)
[ "$rc" = 0 ] && grep -q ' -O exit ' "$WORK/state/log" && [ ! -e "$WORK/state/master" ] \
    && pass "stop ends its own tunnel" || fail "stop: exit $rc"
: > "$WORK/state/log"
rc=$(run stop)
! grep -q ' -O exit ' "$WORK/state/log" && pass "stop with no tunnel touches nothing" \
    || fail "stop with no tunnel sent -O exit"

# --- port held by something else: refuse, kill nothing ---------------------
reset
touch "$WORK/state/busy"
rc=$(run)
[ "$rc" != 0 ] && [ "$(starts)" = 0 ] && [ "$(opens)" = 0 ] \
    && pass "a foreign listener on 15900 is left alone, nothing opened" \
    || fail "busy port: exit $rc, starts $(starts), opens $(opens)"
grep -q -- '-O exit' "$WORK/state/log" && fail "busy port: sent -O exit" || true

# --- stale control socket from a dead tunnel is replaced -------------------
reset
touch "$WORK/home/.ssh/marshbox-screen.sock"
rc=$(run)
[ "$rc" = 0 ] && [ "$(starts)" = 1 ] && [ "$(opens)" = 1 ] \
    && pass "a stale control socket is cleared and the tunnel starts" \
    || fail "stale socket: exit $rc, starts $(starts), opens $(opens): $(cat "$WORK/out")"

# --- tunnel fails to come up: say so, don't open ---------------------------
reset
touch "$WORK/state/fail_start"
rc=$(run)
[ "$rc" != 0 ] && [ "$(opens)" = 0 ] && pass "failed tunnel: non-zero exit, Screen Sharing not opened" \
    || fail "failed tunnel: exit $rc, opens $(opens)"

# --- tunnel up but no VNC server on marshbox: say so, do not open ----------
reset
rm "$WORK/state/server"
rc=$(run)
[ "$rc" != 0 ] && [ "$(opens)" = 0 ] && grep -q "nothing listens on marshbox" "$WORK/out" \
    && pass "no VNC listener on marshbox: clear message, Screen Sharing not opened" \
    || fail "no server: exit $rc, opens $(opens): $(cat "$WORK/out")"

# --- one start/stop at a time ------------------------------------------------
lockfile="$WORK/home/.ssh/marshbox-screen.lock"
# hold_lock SECONDS: hold the same kernel lock from another process.
hold_lock() {
    exec perl -MFcntl=:flock -e 'open(my $l, ">>", $ARGV[0]) or die; flock($l, LOCK_EX) or die; print "held\n"; $| = 1; sleep $ARGV[1]' "$lockfile" "$1"
}
reset
hold_lock 6 > "$WORK/held" & holder=$!
until [ -s "$WORK/held" ]; do sleep 0.1; done
rc=$(run)
[ "$rc" != 0 ] && [ "$(starts)" = 0 ] && [ "$(opens)" = 0 ] && grep -q "another marshbox-screen" "$WORK/out" \
    && pass "while another run holds the lock: no start, no socket removal, clear message" \
    || fail "held lock: exit $rc, starts $(starts), opens $(opens): $(cat "$WORK/out")"
# The holder dies without any cleanup: the kernel drops the lock with it.
kill -9 "$holder"; wait "$holder" 2>/dev/null || true
rc=$(run)
[ "$rc" = 0 ] && [ "$(starts)" = 1 ] && pass "a lock holder that died leaves nothing to clean up" \
    || fail "after holder died: exit $rc, starts $(starts): $(cat "$WORK/out")"

# Two real runs at once, the first one slow to bring its tunnel up: exactly
# one tunnel starts, it keeps its control socket, and stop can end it.
reset
touch "$WORK/state/slow_start"
run > "$WORK/rc_a" & a=$!
sleep 0.5
rc_b=$(run)
wait "$a"
[ "$(cat "$WORK/rc_a")" = 0 ] && [ "$rc_b" = 0 ] && [ "$(starts)" = 1 ] && [ "$(opens)" = 2 ] \
    && [ -e "$WORK/home/.ssh/marshbox-screen.sock" ] \
    && pass "two runs at once: one tunnel, both open Screen Sharing, socket kept" \
    || fail "concurrent: a=$(cat "$WORK/rc_a") b=$rc_b starts $(starts) opens $(opens)"
rc=$(run stop)
[ "$rc" = 0 ] && [ ! -e "$WORK/state/master" ] && pass "and stop still ends that tunnel" \
    || fail "stop after concurrent start: exit $rc"

# --- stop that fails is reported --------------------------------------------
reset
run >/dev/null
touch "$WORK/state/exit_fail"
rc=$(run stop)
[ "$rc" != 0 ] && grep -q "did not stop" "$WORK/out" && pass "a failed stop is reported, not called success" \
    || fail "failed stop: exit $rc: $(cat "$WORK/out")"

# --- Screen Sharing fails to open: say so, leave the tunnel -----------------
reset
touch "$WORK/state/open_fail"
rc=$(run)
[ "$rc" != 0 ] && [ -e "$WORK/state/master" ] && grep -q "tunnel stays up" "$WORK/out" \
    && pass "viewer launch failure: non-zero, tunnel kept and said so" \
    || fail "open failure: exit $rc: $(cat "$WORK/out")"

# --- usage -------------------------------------------------------------------
reset
rc=$(run bogus)
[ "$rc" != 0 ] && [ "$(starts)" = 0 ] && pass "unknown argument is rejected" || fail "bogus: exit $rc"

# Across every case above: the VNC port itself was never connected to.
[ ! -e "$WORK/probes" ] && pass "never connects to the VNC port itself (no blacklist hits)" \
    || fail "connected to the VNC port $(wc -l < "$WORK/probes") time(s)"

echo
[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failure(s)" >&2; exit 1; }
