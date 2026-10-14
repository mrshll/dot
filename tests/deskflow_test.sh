#!/usr/bin/env bash
# Regression test for Deskflow: the Mac shares its keyboard and mouse as the
# server, marshbox is the one client, and no other machine gets any of it.
#
# Renders the chezmoi source into throwaway homes as the Mac, marshbox,
# serveserve and another Linux box; runs the Deskflow.conf modify scripts
# under every awk on this machine (the Mac runs BSD awk); and runs install.sh
# against a PATH of stubs. Nothing is applied to the real home and nothing is
# installed.
#
# Usage: tests/deskflow_test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MAC_HOME_DIR=/Users/tester
MAC_CONF=Library/Deskflow/Deskflow.conf
BOX_CONF=.var/app/org.deskflow.deskflow/config/Deskflow/Deskflow.conf

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
pass() { printf 'ok:   %s\n' "$*"; }

# chez CMD MACHINE HOME [ARG...]: run chezmoi CMD as MACHINE (mac, marshbox,
# serveserve, otherlinux) with HOME as the destination. HOMEDIR, if set, is
# the home directory the templates see.
chez() {
    local cmd=$1 machine=$2 home=$3 os hostname is_server=false homedir
    shift 3
    case $machine in
        mac) os=darwin hostname=test-mac homedir=$MAC_HOME_DIR ;;
        marshbox) os=linux hostname=marshbox homedir=/home/tester ;;
        serveserve) os=linux hostname=serveserve is_server=true homedir=/home/tester ;;
        otherlinux) os=linux hostname=otherlinux homedir=/home/tester ;;
    esac
    homedir=${HOMEDIR:-$homedir}
    cat > "$WORK/chezmoi-$machine.toml" <<EOF
[data]
  hostname = "$hostname"
  os = "$os"
  is_server = $is_server
  has_op = false
EOF
    chezmoi "$cmd" "$@" \
        --source "$REPO_DIR" \
        --destination "$home" \
        --config "$WORK/chezmoi-$machine.toml" \
        --cache "$WORK/cache-$machine" \
        --persistent-state "$home.boltdb" \
        --override-data "{\"chezmoi\":{\"os\":\"$os\",\"hostname\":\"$hostname\",\"homeDir\":\"$homedir\"}}" \
        --no-tty
}

# --- 1. which machines get what ----------------------------------------------

for machine in mac marshbox serveserve otherlinux; do
    chez managed "$machine" "$WORK/managed-$machine" > "$WORK/managed-$machine.txt"
done
has() { grep -qx "$2" "$WORK/managed-$1.txt"; }
under() { grep -E "^$2(/|$)" "$WORK/managed-$1.txt" || true; }

for target in Library/Deskflow/Deskflow.conf Library/Deskflow/deskflow-server.conf \
    Library/LaunchAgents/com.marsh.deskflow.plist; do
    has mac "$target" && pass "mac: manages $target" || fail "mac: does not manage $target"
done
for dir in .var .config/autostart; do
    got=$(under mac "$dir")
    [ -z "$got" ] && pass "mac: nothing under $dir" || fail "mac: manages $(tr '\n' ' ' <<< "$got")"
done

for target in "$BOX_CONF" .config/autostart/org.deskflow.deskflow.desktop; do
    has marshbox "$target" && pass "marshbox: manages $target" || fail "marshbox: does not manage $target"
done
got=$(under marshbox Library)
[ -z "$got" ] && pass "marshbox: nothing under Library" || fail "marshbox: manages $(tr '\n' ' ' <<< "$got")"

for machine in serveserve otherlinux; do
    # plans/ is the untracked working plan, not a target that ships.
    got=$( { grep -Ei 'deskflow' "$WORK/managed-$machine.txt" | grep -v '^plans/' || true
        under "$machine" '(\.var|\.config/autostart|Library)'; } )
    [ -z "$got" ] && pass "$machine: no Deskflow, .var, .config/autostart or Library" \
        || fail "$machine: manages $(tr '\n' ' ' <<< "$got")"
done

# --- 2. the Deskflow.conf modify scripts ------------------------------------

MAC_FRESH="[core]
coreMode=2
computerName=macbook

[gui]
startCoreWithGui=true

[security]
tlsEnabled=true
checkPeerFingerprints=true

[server]
externalConfig=true
externalConfigFile=$MAC_HOME_DIR/Library/Deskflow/deskflow-server.conf
"
BOX_FRESH="[core]
coreMode=1
computerName=marshbox

[gui]
startCoreWithGui=true

[security]
tlsEnabled=true
checkPeerFingerprints=true
"

# What the GUI leaves behind, with CRLF line endings: owned
# keys with wrong values (one duplicated), keys we do not own, sections in
# an order of the GUI's choosing, a client remoteHost set in the GUI.
BOX_EXISTING="[General]
someKey=1

[client]
remoteHost=example
binaryPath=/app/bin/deskflow-client

[core]
lastVersion=1.20.1
computerName=wrongname
coreMode=0
port=24800
computerName=dup

[security]
tlsEnabled=false

[gui]
windowGeometry=@ByteArray(\\x1=abc)
"
BOX_EXPECTED="[General]
someKey=1

[client]
remoteHost=example
binaryPath=/app/bin/deskflow-client

[core]
lastVersion=1.20.1
computerName=marshbox
coreMode=1
port=24800

[security]
tlsEnabled=true
checkPeerFingerprints=true

[gui]
windowGeometry=@ByteArray(\\x1=abc)
startCoreWithGui=true
"
# With remote-host beside Deskflow.conf, client/remoteHost is ours: it
# replaces the old value, duplicates go, and [client] is added if missing.
CLIENT_BLOCK="[client]
remoteHost=example
binaryPath=/app/bin/deskflow-client

"
BOX_HOSTED="${BOX_EXPECTED/remoteHost=example/remoteHost=newhost}"
BOX_EXISTING_DUP="${BOX_EXISTING/binaryPath=/remoteHost=stale
binaryPath=}"
BOX_NOCLIENT="${BOX_EXISTING/"$CLIENT_BLOCK"/}"
BOX_NOCLIENT_HOSTED="${BOX_EXPECTED/"$CLIENT_BLOCK"/}
[client]
remoteHost=newhost
"
BOX_FRESH_HOSTED="$BOX_FRESH
[client]
remoteHost=newhost
"
MAC_EXISTING="[General]
someKey=1

[gui]
startCoreWithGui=false
startCoreWithGui=true
closeToTray=true

[core]
coreMode=1
lastVersion=1.20.1

[client]
remoteHost=example

[server]
externalConfig=false
externalConfigFile=/somewhere/else.conf
"
MAC_EXPECTED="[General]
someKey=1

[gui]
startCoreWithGui=true
closeToTray=true

[core]
coreMode=2
lastVersion=1.20.1
computerName=macbook

[client]
remoteHost=example

[server]
externalConfig=true
externalConfigFile=$MAC_HOME_DIR/Library/Deskflow/deskflow-server.conf

[security]
tlsEnabled=true
checkPeerFingerprints=true
"

# Every awk on this box, each put first on PATH as `awk` for the render.
awks=()
for candidate in mawk gawk original-awk nawk "busybox awk"; do
    set -- $candidate
    bin=$(command -v "$1" || true)
    [ -n "$bin" ] || continue
    real=$(readlink -f "$bin")
    if [ "$1" = busybox ]; then
        "$bin" awk 'BEGIN{}' 2>/dev/null || continue
    else
        # nawk is often an alternatives link to mawk; run each awk once.
        for seen in ${awks[@]+"${awks[@]}"}; do
            [ "$(readlink -f "$(cut -d: -f2 <<< "$seen")")" = "$real" ] && continue 2
        done
    fi
    awks+=("$1:$bin")
done
pass "awks found: $(for a in "${awks[@]}"; do printf '%s ' "${a%%:*}"; done)"

# modify_case AWK MACHINE CONF TARGET LABEL INPUT EXPECTED [HOST [REMOTE]]:
# apply TARGET over CONF holding INPUT (absent if INPUT is "-"), with HOST in
# remote-host beside it (absent if "-"), and compare with EXPECTED; the file
# must hold exactly one remoteHost=REMOTE (unchecked if "-"). Then apply
# again and require no change.
modify_case() {
    local awk_name=$1 awk_bin=$2 machine=$3 conf=$4 target=$5 label=$6 input=$7 expected=$8
    local host=${9--} remote=${10--} homedir=
    local home="$WORK/modify-$machine-$awk_name-$RANDOM" awkdir="$WORK/awk-$awk_name"
    mkdir -p "$awkdir" "$home/$(dirname "$conf")"
    ln -sf "$awk_bin" "$awkdir/awk"
    if [ "$input" != - ]; then
        printf '%s' "$input" | sed 's/$/\r/' > "$home/$conf"
    fi
    [ "$host" != - ] && printf '%s' "$host" > "$home/$(dirname "$conf")/remote-host"
    # marshbox's script reads remote-host from the home it renders for.
    [ "$machine" = marshbox ] && homedir=$home
    HOMEDIR=$homedir PATH="$awkdir:$PATH" chez apply "$machine" "$home" "$home/$target" --force
    if printf '%s' "$expected" | cmp -s - "$home/$conf"; then
        pass "$machine/$awk_name: $label gives the expected file"
    else
        fail "$machine/$awk_name: $label gave:"
        printf '%s' "$expected" | diff - "$home/$conf" | sed 's/^/      /' >&2 || true
    fi
    if grep -q $'\r' "$home/$conf"; then
        fail "$machine/$awk_name: $label left a CR"
    fi
    if [ "$remote" != - ]; then
        [ "$(grep -c '^remoteHost=' "$home/$conf")" = 1 ] && grep -qx "remoteHost=$remote" "$home/$conf" \
            && pass "$machine/$awk_name: $label has remoteHost=$remote once" \
            || fail "$machine/$awk_name: $label remoteHost is: $(grep '^remoteHost=' "$home/$conf" | tr '\n' ' ')"
    fi
    cp "$home/$conf" "$WORK/before"
    HOMEDIR=$homedir PATH="$awkdir:$PATH" chez apply "$machine" "$home" "$home/$target" --force
    cmp -s "$WORK/before" "$home/$conf" \
        && pass "$machine/$awk_name: $label is unchanged by a second apply" \
        || fail "$machine/$awk_name: $label changes on a second apply"
}

for entry in "${awks[@]}"; do
    name=${entry%%:*} bin=${entry#*:}
    # busybox dispatches on argv[0], so a link named awk is busybox awk.
    modify_case "$name" "$bin" mac "$MAC_CONF" Library/Deskflow "no existing file" - "$MAC_FRESH"
    modify_case "$name" "$bin" mac "$MAC_CONF" Library/Deskflow "a GUI-written CRLF file" \
        "$MAC_EXISTING" "$MAC_EXPECTED" - example
    modify_case "$name" "$bin" marshbox "$BOX_CONF" .var "no existing file" - "$BOX_FRESH"
    modify_case "$name" "$bin" marshbox "$BOX_CONF" .var "a GUI-written CRLF file" \
        "$BOX_EXISTING" "$BOX_EXPECTED" - example
    # remote-host, a placeholder name padded with whitespace.
    modify_case "$name" "$bin" marshbox "$BOX_CONF" .var "remote-host, no existing file" \
        - "$BOX_FRESH_HOSTED" $' newhost \n' newhost
    modify_case "$name" "$bin" marshbox "$BOX_CONF" .var "remote-host over an old remoteHost" \
        "$BOX_EXISTING_DUP" "$BOX_HOSTED" $' newhost \n' newhost
    modify_case "$name" "$bin" marshbox "$BOX_CONF" .var "remote-host, no [client] section" \
        "$BOX_NOCLIENT" "$BOX_NOCLIENT_HOSTED" $' newhost \n' newhost
    modify_case "$name" "$bin" marshbox "$BOX_CONF" .var "an empty remote-host" \
        "$BOX_EXISTING" "$BOX_EXPECTED" "" example
    modify_case "$name" "$bin" marshbox "$BOX_CONF" .var "a whitespace-only remote-host" \
        "$BOX_EXISTING" "$BOX_EXPECTED" $' \t\n' example
done

# --- 3. names and layout agree ----------------------------------------------

layout="$REPO_DIR/Library/Deskflow/deskflow-server.conf"
screens=$(awk '/^section: screens/{s=1;next} /^end/{s=0} s && /:[ \t]*$/{gsub(/[ \t:]/,""); print}' "$layout")
for name in macbook marshbox; do
    grep -qx "$name" <<< "$screens" && pass "layout: $name is a screen" || fail "layout: no screen $name"
done
for name in $(printf '%s%s' "$MAC_FRESH" "$BOX_FRESH" | sed -n 's/^computerName=//p'); do
    grep -qx "$name" <<< "$screens" && pass "layout: computerName $name has a screen" \
        || fail "layout: computerName $name has no screen"
done
# Every link a: dir = b has its mirror b: opposite = a.
links=$(awk '/^section: links/{s=1;next} /^end/{s=0}
    s && /:[ \t]*$/ {from=$1; sub(/:$/,"",from); next}
    s && /=/ {print from, $1, $3}' "$layout")
[ -n "$links" ] || fail "layout: no links"
while read -r from dir to; do
    case $dir in
        left) opp=right ;; right) opp=left ;; up) opp=down ;; down) opp=up ;; *) opp=? ;;
    esac
    grep -qx "$to $opp $from" <<< "$links" && pass "layout: $from $dir $to is mirrored" \
        || fail "layout: $from $dir $to has no $to $opp $from"
done <<< "$links"

# --- 4. starting at login ----------------------------------------------------

plist_check=$(uv run --no-project python -c '
import plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
assert p["ProgramArguments"] == ["/usr/bin/open", "-a", "/Applications/Deskflow.app"], p["ProgramArguments"]
assert p["RunAtLoad"] is True, p.get("RunAtLoad")
assert "KeepAlive" not in p, p["KeepAlive"]
assert p["Label"] == "com.marsh.deskflow", p["Label"]
print("ok")
' "$REPO_DIR/Library/LaunchAgents/com.marsh.deskflow.plist" 2>&1) || true
[ "$plist_check" = ok ] && pass "plist: opens Deskflow.app at load, no KeepAlive" \
    || fail "plist: $plist_check"

exec_line=$(grep '^Exec=' "$REPO_DIR/dot_config/autostart/org.deskflow.deskflow.desktop")
[ "$exec_line" = "Exec=flatpak run org.deskflow.deskflow" ] && pass "autostart: runs the flatpak" \
    || fail "autostart: $exec_line"

# --- 5. install.sh -----------------------------------------------------------

stubs="$WORK/bin"
mkdir -p "$stubs"
for tool in bash sh mkdir chmod; do
    ln -s "$(command -v "$tool")" "$stubs/$tool"
done
printf '#!/bin/sh\necho Linux\n' > "$stubs/uname"
printf '#!/bin/sh\necho "$STUB_HOSTNAME"\n' > "$stubs/hostname"
cat > "$stubs/sudo" <<'EOF'
#!/bin/sh
echo "sudo $*" >> "$LOG"
exit 1
EOF
cat > "$stubs/curl" <<'EOF'
#!/bin/sh
echo "curl $*" >> "$LOG"
echo 'mkdir -p "$2"; : > "$2/chezmoi"; chmod +x "$2/chezmoi"'
EOF
cat > "$WORK/flatpak" <<'EOF'
#!/bin/sh
echo "flatpak $*" >> "$LOG"
[ "$1" = info ] && exit "${FLATPAK_INFO:-1}"
exit 0
EOF
chmod +x "$stubs/uname" "$stubs/hostname" "$stubs/sudo" "$stubs/curl" "$WORK/flatpak"

# run_install LABEL HOSTNAME FLATPAK(yes/no) [FLATPAK_INFO]
run_install() {
    local label=$1 host=$2 with_flatpak=$3 info=${4:-1}
    rm -rf "$WORK/home" "$stubs/flatpak"
    mkdir -p "$WORK/home"
    [ "$with_flatpak" = yes ] && ln -s "$WORK/flatpak" "$stubs/flatpak"
    : > "$WORK/log"
    if env -i HOME="$WORK/home" PATH="$stubs" LOG="$WORK/log" STUB_HOSTNAME="$host" \
        FLATPAK_INFO="$info" "$stubs/bash" "$REPO_DIR/setup/install.sh" </dev/null \
        > "$WORK/out" 2>&1; then
        pass "install ($label): exits 0"
    else
        fail "install ($label): exited non-zero: $(tail -n3 "$WORK/out" | tr '\n' ';')"
    fi
    if grep -v '^sudo -n true$' "$WORK/log" | grep -q '^sudo'; then
        fail "install ($label): ran sudo beyond the probe: $(grep '^sudo' "$WORK/log" | sort -u | tr '\n' ';')"
    fi
}
flatpak_calls() { grep '^flatpak' "$WORK/log" || true; }

run_install "marshbox, no flatpak" marshbox no
grep -q 'deskflow not installed — needs flatpak' "$WORK/out" \
    && pass "install (marshbox, no flatpak): warns deskflow needs flatpak" \
    || fail "install (marshbox, no flatpak): no flatpak warning"
[ -z "$(flatpak_calls)" ] && pass "install (marshbox, no flatpak): flatpak never called" \
    || fail "install (marshbox, no flatpak): called $(flatpak_calls)"

run_install "marshbox, deskflow missing" marshbox yes 1
want="flatpak info --user org.deskflow.deskflow
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user --noninteractive flathub org.deskflow.deskflow"
[ "$(flatpak_calls)" = "$want" ] \
    && pass "install (marshbox, deskflow missing): adds Flathub and installs per user" \
    || fail "install (marshbox, deskflow missing): flatpak calls: $(flatpak_calls | tr '\n' ';')"

run_install "marshbox, deskflow present" marshbox yes 0
[ "$(flatpak_calls)" = "flatpak info --user org.deskflow.deskflow" ] \
    && pass "install (marshbox, deskflow present): installs nothing" \
    || fail "install (marshbox, deskflow present): flatpak calls: $(flatpak_calls | tr '\n' ';')"

run_install "serveserve" serveserve yes 1
[ -z "$(flatpak_calls)" ] && pass "install (serveserve): flatpak never called" \
    || fail "install (serveserve): called $(flatpak_calls | tr '\n' ';')"
! grep -qi deskflow "$WORK/out" && pass "install (serveserve): says nothing about deskflow" \
    || fail "install (serveserve): mentions deskflow"

echo
if [ "$failures" -ne 0 ]; then
    echo "$failures failure(s)" >&2
    exit 1
fi
echo "all passed"
