#!/usr/bin/env bash
# Regression test for the passh RemoteForward in ~/.ssh (private_dot_ssh/).
#
# Renders the chezmoi source into a throwaway home as the Mac and as the
# server, then asks `ssh -G` which forwards each destination would get.
# Nothing is applied to the real home and nothing connects anywhere.
#
# Usage: tests/passh_ssh_test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FORWARD="remoteforward 18340 [127.0.0.1]:18340"
FORWARDED=(serveserve serveserve.local 100.72.11.128 marshbox marshbox.local 192.168.1.102)
# The stale marshbox Tailscale address, near-miss names, and unrelated hosts.
NOT_FORWARDED=(100.106.61.56 github.com serveserve.example marshbox.example 192.168.1.10 localhost)
# The targets the PR tells the Mac to apply: the directory, not the file in
# it, so a first install creates config.d.
MAC_TARGETS=(.ssh/config .ssh/config.d)

# Stands in for the Mac's hand-maintained config: a global directive that must
# keep applying everywhere, and an existing alias block that already carries
# the forward, which the include must not double up.
EXISTING_CONFIG='ServerAliveInterval 30

Host serveserve
  HostName serveserve.local
  RemoteForward 18340 127.0.0.1:18340

Host github.com
  User git
'

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
pass() { printf 'ok:   %s\n' "$*"; }

# apply OS HOME TARGET...: as if chezmoi ran on OS, apply TARGETs (relative to
# HOME) into HOME.
apply() {
    local os=$1 home=$2 target targets=()
    shift 2
    for target in "$@"; do targets+=("$home/$target"); done
    cat > "$WORK/chezmoi-$os.toml" <<EOF
[data]
  hostname = "test-$os"
  os = "$os"
  is_server = false
  has_op = false
EOF
    chezmoi apply "${targets[@]}" \
        --source "$REPO_DIR" \
        --destination "$home" \
        --config "$WORK/chezmoi-$os.toml" \
        --cache "$WORK/cache-$os" \
        --persistent-state "$WORK/state-$os.boltdb" \
        --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" \
        --no-tty --force
}

# forwards_for CONFIG HOST: the RemoteForward lines ssh would use.
forwards_for() {
    ssh -G -F "$1" "$2" </dev/null 2>/dev/null | grep '^remoteforward ' || true
}

# --- the Mac ----------------------------------------------------------------

mac="$WORK/mac"
mkdir -p "$mac/.ssh"
chmod 700 "$mac/.ssh"
printf "%s" "$EXISTING_CONFIG" > "$WORK/existing"
cp "$WORK/existing" "$mac/.ssh/config"
chmod 600 "$mac/.ssh/config"

apply darwin "$mac" "${MAC_TARGETS[@]}"

first_line=$(head -n1 "$mac/.ssh/config")
if [ "$first_line" = "Include ~/.ssh/config.d/passh" ]; then
    pass "mac: include is the first line of ~/.ssh/config"
else
    fail "mac: first line is '$first_line'"
fi

if { echo "Include ~/.ssh/config.d/passh"; cat "$WORK/existing"; } | cmp -s - "$mac/.ssh/config"; then
    pass "mac: existing config preserved byte for byte after the include"
else
    fail "mac: existing config changed"
fi

before=$(cksum < "$mac/.ssh/config")
apply darwin "$mac" "${MAC_TARGETS[@]}"
if [ "$(cksum < "$mac/.ssh/config")" = "$before" ]; then
    pass "mac: re-apply is idempotent"
else
    fail "mac: re-apply changed ~/.ssh/config"
fi

mode=$(stat -c %a "$mac/.ssh/config" 2>/dev/null || stat -f %Lp "$mac/.ssh/config")
[ "$mode" = 600 ] && pass "mac: ~/.ssh/config stays 0600" || fail "mac: ~/.ssh/config mode $mode"

# ssh expands ~ from the passwd entry, not \$HOME, so point the include at the
# throwaway home before asking ssh what it would do.
resolved="$WORK/resolved_config"
sed "s|~/.ssh/|$mac/.ssh/|" "$mac/.ssh/config" > "$resolved"

for host in "${FORWARDED[@]}"; do
    got=$(forwards_for "$resolved" "$host")
    if [ "$got" = "$FORWARD" ]; then
        pass "mac: $host gets exactly one loopback forward"
    else
        fail "mac: $host forwards: '${got:-none}'"
    fi
done

for host in "${NOT_FORWARDED[@]}"; do
    got=$(forwards_for "$resolved" "$host")
    if [ -z "$got" ]; then
        pass "mac: $host gets no forward"
    else
        fail "mac: $host forwards: '$got'"
    fi
done

alive=$(ssh -G -F "$resolved" github.com </dev/null 2>/dev/null | grep '^serveraliveinterval ' || true)
[ "$alive" = "serveraliveinterval 30" ] && pass "mac: global directive still applies after the include" \
    || fail "mac: github.com serveraliveinterval is '${alive:-unset}'"

# Every forward in the fragment must bind the remote end to loopback only
# (no bind address, so sshd's GatewayPorts=no default applies) and point at
# the Mac's loopback passhd.
bad=$(grep -i '^[[:space:]]*remoteforward' "$mac/.ssh/config.d/passh" \
    | grep -v '^[[:space:]]*RemoteForward 18340 127\.0\.0\.1:18340$' || true)
[ -z "$bad" ] && pass "mac: fragment forwards only 18340 -> 127.0.0.1:18340" \
    || fail "mac: unexpected forward lines: $bad"

# A Mac with ~/.ssh but no ~/.ssh/config yet gets just the include.
fresh="$WORK/fresh"
mkdir -p "$fresh/.ssh"
apply darwin "$fresh" "${MAC_TARGETS[@]}"
if printf "Include ~/.ssh/config.d/passh\n" | cmp -s - "$fresh/.ssh/config"; then
    pass "mac: missing ~/.ssh/config is created with only the include"
else
    fail "mac: fresh ~/.ssh/config is '$(cat "$fresh/.ssh/config")'"
fi

# An include already on the first line, with no trailing newline, is left alone.
bare="$WORK/bare"
mkdir -p "$bare/.ssh"
printf 'Include ~/.ssh/config.d/passh' > "$bare/.ssh/config"
apply darwin "$bare" "${MAC_TARGETS[@]}"
if printf "Include ~/.ssh/config.d/passh" | cmp -s - "$bare/.ssh/config"; then
    pass "mac: existing include without a newline is not duplicated"
else
    fail "mac: config became '$(cat "$bare/.ssh/config")'"
fi

# --- the server -------------------------------------------------------------

server="$WORK/server"
mkdir -p "$server/.ssh"
cp "$WORK/existing" "$server/.ssh/config"

apply linux "$server" .ssh

if cmp -s "$WORK/existing" "$server/.ssh/config"; then
    pass "server: ~/.ssh/config untouched"
else
    fail "server: ~/.ssh/config changed"
fi
if [ ! -e "$server/.ssh/config.d" ]; then
    pass "server: no forward fragment installed"
else
    fail "server: ~/.ssh/config.d was created"
fi

echo
if [ "$failures" -ne 0 ]; then
    echo "$failures failure(s)" >&2
    exit 1
fi
echo "all passed"
