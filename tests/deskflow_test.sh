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

for target in Library/Deskflow/Deskflow.conf Library/Deskflow/deskflow-server.conf; do
    has mac "$target" && pass "mac: manages $target" || fail "mac: does not manage $target"
done
# Deskflow starts on the Mac only by hand, so it never comes up at login on
# whatever network the Mac is on.
got=$(grep -i deskflow "$WORK/managed-mac.txt" | grep -Ev '^Library/Deskflow(/|$)' || true)
[ -z "$got" ] && pass "mac: nothing starts Deskflow at login" \
    || fail "mac: manages $(tr '\n' ' ' <<< "$got")"
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

# The runbook's first apply, into fresh homes: only the directories it tells
# you to create exist beforehand, and only its targets are applied.
runbook="$WORK/runbook-mac"
mkdir -p "$runbook/Library"
if chez apply mac "$runbook" "$runbook/Library/Deskflow" > "$WORK/out" 2>&1; then
    missing=
    for f in Library/Deskflow/Deskflow.conf Library/Deskflow/deskflow-server.conf; do
        [ -s "$runbook/$f" ] || missing+="$f "
    done
    [ -z "$missing" ] && pass "runbook (mac): apply creates Deskflow.conf and the layout" \
        || fail "runbook (mac): apply succeeded but missing $missing"
else
    fail "runbook (mac): apply failed: $(tr '\n' ';' < "$WORK/out")"
fi
runbook="$WORK/runbook-marshbox"
mkdir -p "$runbook/.var/app/org.deskflow.deskflow/config/Deskflow" "$runbook/.config/autostart"
if HOMEDIR=$runbook chez apply marshbox "$runbook" "$runbook/.var/app/org.deskflow.deskflow" \
    "$runbook/.config/autostart/org.deskflow.deskflow.desktop" > "$WORK/out" 2>&1; then
    missing=
    for f in "$BOX_CONF" .config/autostart/org.deskflow.deskflow.desktop; do
        [ -s "$runbook/$f" ] || missing+="$f "
    done
    [ -z "$missing" ] && pass "runbook (marshbox): apply creates Deskflow.conf and the autostart entry" \
        || fail "runbook (marshbox): apply succeeded but missing $missing"
else
    fail "runbook (marshbox): apply failed: $(tr '\n' ';' < "$WORK/out")"
fi

# --- 2. the Deskflow.conf modify scripts ------------------------------------

# Expected files hold @ADDR@ where the owned address goes: core/interface on
# the Mac, client/remoteHost on marshbox.
MAC_FRESH="[core]
coreMode=2
computerName=marshtop
interface=@ADDR@

[gui]
startCoreWithGui=true

[security]
tlsEnabled=true
checkPeerFingerprints=true

[server]
externalConfig=true
externalConfigFile=$MAC_HOME_DIR/Library/Deskflow/deskflow-server.conf
"
BOX_FRESH="[client]
remoteHost=@ADDR@

[core]
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
remoteHost=@ADDR@
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
# client/remoteHost is always ours: it replaces the old value, duplicates
# go, and [client] is added if missing.
BOX_EXISTING_DUP="${BOX_EXISTING/binaryPath=/remoteHost=stale
binaryPath=}"
BOX_NOCLIENT="${BOX_EXISTING/"[client]
remoteHost=example
binaryPath=/app/bin/deskflow-client

"/}"
BOX_NOCLIENT_EXPECTED="${BOX_EXPECTED/"[client]
remoteHost=@ADDR@
binaryPath=/app/bin/deskflow-client

"/}
[client]
remoteHost=@ADDR@
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
computerName=marshtop
interface=@ADDR@

[client]
remoteHost=example

[server]
externalConfig=true
externalConfigFile=$MAC_HOME_DIR/Library/Deskflow/deskflow-server.conf

[security]
tlsEnabled=true
checkPeerFingerprints=true
"
# An interface the GUI set to every interface, then again to another value:
# the first is replaced in place and the repeat dropped.
MAC_EXISTING_IFACE="${MAC_EXISTING/lastVersion=1.20.1/interface=0.0.0.0
lastVersion=1.20.1
interface=10.9.9.9}"
MAC_EXPECTED_IFACE="${MAC_EXPECTED/"coreMode=2
lastVersion=1.20.1
computerName=marshtop
interface=@ADDR@"/"coreMode=2
interface=@ADDR@
lastVersion=1.20.1
computerName=marshtop"}"

# resolve PATH: the executable PATH finally points at.
resolve() {
    readlink -f "$1" 2>/dev/null || realpath "$1" 2>/dev/null || printf '%s\n' "$1"
}

# Every awk on this box, each put first on PATH as `awk` for the render: the
# default awk, /usr/bin/awk if something shadows it, and every other awk
# found by name. Each executable runs once, however many names lead to it
# (nawk and awk are often alternatives links to mawk). busybox dispatches on
# argv[0], so a link named awk to it is busybox awk.
awks=() reals=" "
for candidate in awk /usr/bin/awk mawk gawk original-awk nawk onetrue-awk bwk-awk "busybox awk"; do
    set -- $candidate
    bin=$(command -v "$1" || true)
    [ -n "$bin" ] || continue
    real=$(resolve "$bin")
    case $reals in *" $real "*) continue ;; esac
    if [ "$1" = busybox ]; then
        "$bin" awk 'BEGIN{}' </dev/null 2>/dev/null || continue
    else
        "$bin" 'BEGIN{}' </dev/null 2>/dev/null || continue
    fi
    name=${real##*/}
    case " ${awks[*]+${awks[*]%%:*}} " in *" $name "*) name=$name-${#awks[@]} ;; esac
    awks+=("$name:$real") reals+="$real "
done
if [ ${#awks[@]} -eq 0 ]; then
    fail "no awk found; the modify scripts are untested"
else
    pass "awks found: $(for a in "${awks[@]}"; do printf '%s ' "${a%%:*}"; done)"
fi

# modify_case AWK MACHINE CONF TARGET LABEL INPUT EXPECTED [FILE [ADDR]]:
# apply TARGET over CONF holding INPUT (absent if INPUT is "-"), with FILE
# as the address file beside it (listen-address on the Mac, remote-host on
# marshbox; absent if "-"), and compare with EXPECTED, its @ADDR@ standing
# for ADDR (default 127.0.0.1). The file must hold exactly one owned address
# line, interface=ADDR or remoteHost=ADDR. Then apply again and require no
# change.
modify_case() {
    local awk_name=$1 awk_bin=$2 machine=$3 conf=$4 target=$5 label=$6 input=$7 expected=$8
    local file=${9--} addr=${10:-127.0.0.1} addr_file key
    local home="$WORK/modify-$machine-$awk_name-$RANDOM" awkdir="$WORK/awk-$awk_name"
    case $machine in
        mac) addr_file=listen-address key=interface ;;
        marshbox) addr_file=remote-host key=remoteHost ;;
    esac
    mkdir -p "$awkdir" "$home/$(dirname "$conf")"
    ln -sf "$awk_bin" "$awkdir/awk"
    if [ "$input" != - ]; then
        printf '%s' "$input" | sed 's/$/\r/' > "$home/$conf"
    fi
    [ "$file" != - ] && printf '%s' "$file" > "$home/$(dirname "$conf")/$addr_file"
    # Both scripts read the address file from the home they render for.
    expected=${expected//@ADDR@/$addr}
    expected=${expected//"$MAC_HOME_DIR"/"$home"}
    HOMEDIR=$home PATH="$awkdir:$PATH" chez apply "$machine" "$home" "$home/$target" --force
    if printf '%s' "$expected" | cmp -s - "$home/$conf"; then
        pass "$machine/$awk_name: $label gives the expected file"
    else
        fail "$machine/$awk_name: $label gave:"
        printf '%s' "$expected" | diff - "$home/$conf" | sed 's/^/      /' >&2 || true
    fi
    if grep -q $'\r' "$home/$conf"; then
        fail "$machine/$awk_name: $label left a CR"
    fi
    [ "$(grep -c "^$key=" "$home/$conf")" = 1 ] && grep -qxF "$key=$addr" "$home/$conf" \
        && pass "$machine/$awk_name: $label has $key=$addr once" \
        || fail "$machine/$awk_name: $label $key is: $(grep "^$key=" "$home/$conf" | tr '\n' ' ')"
    cp "$home/$conf" "$WORK/before"
    HOMEDIR=$home PATH="$awkdir:$PATH" chez apply "$machine" "$home" "$home/$target" --force
    cmp -s "$WORK/before" "$home/$conf" \
        && pass "$machine/$awk_name: $label is unchanged by a second apply" \
        || fail "$machine/$awk_name: $label changes on a second apply"
}

for entry in ${awks[@]+"${awks[@]}"}; do
    name=${entry%%:*} bin=${entry#*:}
    modify_case "$name" "$bin" mac "$MAC_CONF" Library/Deskflow "no existing file" - "$MAC_FRESH"
    modify_case "$name" "$bin" mac "$MAC_CONF" Library/Deskflow "a GUI-written CRLF file" \
        "$MAC_EXISTING" "$MAC_EXPECTED"
    modify_case "$name" "$bin" mac "$MAC_CONF" Library/Deskflow "listen-address, no existing file" \
        - "$MAC_FRESH" $' 192.168.1.10 \n' 192.168.1.10
    modify_case "$name" "$bin" mac "$MAC_CONF" Library/Deskflow "listen-address over a GUI-written file" \
        "$MAC_EXISTING" "$MAC_EXPECTED" $'192.168.1.10\n' 192.168.1.10
    modify_case "$name" "$bin" mac "$MAC_CONF" Library/Deskflow "listen-address over interface=0.0.0.0" \
        "$MAC_EXISTING_IFACE" "$MAC_EXPECTED_IFACE" $'192.168.1.10\n' 192.168.1.10
    modify_case "$name" "$bin" mac "$MAC_CONF" Library/Deskflow "no listen-address over interface=0.0.0.0" \
        "$MAC_EXISTING_IFACE" "$MAC_EXPECTED_IFACE"
    modify_case "$name" "$bin" marshbox "$BOX_CONF" .var "no existing file" - "$BOX_FRESH"
    modify_case "$name" "$bin" marshbox "$BOX_CONF" .var "a GUI-written CRLF file" \
        "$BOX_EXISTING" "$BOX_EXPECTED"
    modify_case "$name" "$bin" marshbox "$BOX_CONF" .var "remote-host, no existing file" \
        - "$BOX_FRESH" $' 192.168.1.10 \n' 192.168.1.10
    modify_case "$name" "$bin" marshbox "$BOX_CONF" .var "remote-host over remoteHost=example" \
        "$BOX_EXISTING" "$BOX_EXPECTED" $'192.168.1.10\n' 192.168.1.10
    modify_case "$name" "$bin" marshbox "$BOX_CONF" .var "remote-host over a duplicated remoteHost" \
        "$BOX_EXISTING_DUP" "$BOX_EXPECTED" $'192.168.1.10\n' 192.168.1.10
    modify_case "$name" "$bin" marshbox "$BOX_CONF" .var "remote-host, no [client] section" \
        "$BOX_NOCLIENT" "$BOX_NOCLIENT_EXPECTED" $'192.168.1.10\n' 192.168.1.10
    modify_case "$name" "$bin" marshbox "$BOX_CONF" .var "an invalid remote-host, no [client] section" \
        "$BOX_NOCLIENT" "$BOX_NOCLIENT_EXPECTED" $'example.local\n'
done

# home_address through both scripts, under the default awk (the address is
# checked by grep, not awk): FILE CONTENTS|EXPECTED ADDRESS|LABEL. "-" is no
# file at all.
address_cases=(
    $'192.168.1.10\n|192.168.1.10|192.168.x.y'
    $'192.168.0.0\n|192.168.0.0|192.168.0.0'
    $'192.168.255.255\n|192.168.255.255|192.168.255.255'
    $'10.0.0.5\n|10.0.0.5|10.x'
    $'10.255.255.255\n|10.255.255.255|10.255.255.255'
    $'172.16.0.1\n|172.16.0.1|172.16.x'
    $'172.20.5.5\n|172.20.5.5|172.20.x'
    $'172.31.255.254\n|172.31.255.254|172.31.x'
    $' \t192.168.1.10 \t\n|192.168.1.10|192.168.x.y padded with whitespace'
    $'\n192.168.1.10\n|127.0.0.1|a blank first line'
    $'192.168.1.10\n8.8.8.8\n|192.168.1.10|a second line, ignored'
    $'192.168.1.10|192.168.1.10|no trailing newline'
    "-|127.0.0.1|no file"
    "|127.0.0.1|an empty file"
    $' \t\n|127.0.0.1|a whitespace-only file'
    $'0.0.0.0\n|127.0.0.1|0.0.0.0'
    $'172.32.0.1\n|127.0.0.1|172.32.0.1'
    $'172.15.0.1\n|127.0.0.1|172.15.0.1'
    $'100.64.0.1\n|127.0.0.1|100.64.0.1 (Tailscale)'
    $'100.127.1.1\n|127.0.0.1|100.127.1.1 (Tailscale)'
    $'8.8.8.8\n|127.0.0.1|8.8.8.8'
    $'127.0.0.1\n|127.0.0.1|127.0.0.1'
    $'256.1.1.1\n|127.0.0.1|256.1.1.1'
    $'192.168.1.256\n|127.0.0.1|192.168.1.256'
    $'192.168.1\n|127.0.0.1|192.168.1'
    $'192.168.1.1.1\n|127.0.0.1|192.168.1.1.1'
    $'example.local\n|127.0.0.1|example.local'
    $'example.ts.net\n|127.0.0.1|example.ts.net'
    $'fe80::1\n|127.0.0.1|fe80::1'
    $'192.168.1.10 extra\n|127.0.0.1|192.168.1.10 extra'
)
if [ ${#awks[@]} -gt 0 ]; then
    name=${awks[0]%%:*} bin=${awks[0]#*:}
    for c in "${address_cases[@]}"; do
        contents=${c%%|*} rest=${c#*|}
        want=${rest%%|*} label=${rest#*|}
        modify_case "$name" "$bin" mac "$MAC_CONF" Library/Deskflow "listen-address $label" \
            "$MAC_EXISTING_IFACE" "$MAC_EXPECTED_IFACE" "$contents" "$want"
        modify_case "$name" "$bin" marshbox "$BOX_CONF" .var "remote-host $label" \
            "$BOX_EXISTING" "$BOX_EXPECTED" "$contents" "$want"
    done
fi

# --- 3. names and layout agree ----------------------------------------------

layout="$REPO_DIR/Library/Deskflow/deskflow-server.conf"
screens=$(awk '/^section: screens/{s=1;next} /^end/{s=0} s && /:[ \t]*$/{gsub(/[ \t:]/,""); print}' "$layout")
for name in marshtop marshbox; do
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

# --- 4. starting at login (marshbox only) ------------------------------------

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
