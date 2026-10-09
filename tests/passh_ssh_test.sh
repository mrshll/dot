#!/usr/bin/env bash
# Regression test for the managed ~/.ssh (private_dot_ssh/): the passh
# RemoteForward on the Mac, the pinned marshbox route on serveserve, nothing
# elsewhere.
#
# Renders the chezmoi source into throwaway homes as the Mac, serveserve and
# another Linux box, then asks `ssh -G` what each destination would get.
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
# What the Mac's ~/.ssh/config must start with: the passh forward, then the
# marshbox identity.
MAC_INCLUDES="Include ~/.ssh/config.d/passh\nInclude ~/.ssh/config.d/marshbox\n"

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
# HOME) into HOME. IS_SERVER=true renders it as serveserve.
apply() {
    local os=$1 home=$2 target targets=()
    shift 2
    for target in "$@"; do targets+=("$home/$target"); done
    # serveserve applies with umask 002; ssh rejects group-writable config.
    cat > "$WORK/chezmoi-$os.toml" <<EOF
umask = 0o002

[data]
  hostname = "test-$os"
  os = "$os"
  is_server = ${IS_SERVER:-false}
  has_op = false
EOF
    chezmoi apply "${targets[@]}" \
        --source "$REPO_DIR" \
        --destination "$home" \
        --config "$WORK/chezmoi-$os.toml" \
        --cache "$WORK/cache-$os" \
        --persistent-state "$home.boltdb" \
        --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" \
        --no-tty --force
}

# private_ssh LABEL HOME: upstream ssh refuses a group- or world-writable file
# read through the user config, Include targets included ("Bad owner or
# permissions"); some distributions relax this for single-user groups.
# BSD-compatible find: either write bit.
private_ssh() {
    local loose
    loose=$(find "$2/.ssh" \( -perm -020 -o -perm -002 \) -print)
    [ -z "$loose" ] && pass "$1: nothing under ~/.ssh is group or world writable" \
        || fail "$1: group/world writable: $(tr "\n" " " <<< "$loose")"
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
private_ssh mac "$mac"

if { printf "$MAC_INCLUDES"; cat "$WORK/existing"; } | cmp -s - "$mac/.ssh/config"; then
    pass "mac: both includes lead ~/.ssh/config, existing config preserved byte for byte"
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

# A Mac with ~/.ssh but no ~/.ssh/config yet gets just the includes.
fresh="$WORK/fresh"
mkdir -p "$fresh/.ssh"
apply darwin "$fresh" "${MAC_TARGETS[@]}"
if printf "$MAC_INCLUDES" | cmp -s - "$fresh/.ssh/config"; then
    pass "mac: missing ~/.ssh/config is created with only the includes"
else
    fail "mac: fresh ~/.ssh/config is '$(cat "$fresh/.ssh/config")'"
fi

# Upgrading a Mac that already has #3's single include, with or without a
# trailing newline, does not duplicate it.
old="$WORK/old"
mkdir -p "$old/.ssh"
{ echo "Include ~/.ssh/config.d/passh"; cat "$WORK/existing"; } > "$old/.ssh/config"
apply darwin "$old" "${MAC_TARGETS[@]}"
if { printf "$MAC_INCLUDES"; cat "$WORK/existing"; } | cmp -s - "$old/.ssh/config"; then
    pass "mac: upgrade from the single passh include adds marshbox once"
else
    fail "mac: upgraded config is .$(head -n3 "$old/.ssh/config" | tr "\n" "|")."
fi
bare="$WORK/bare"
mkdir -p "$bare/.ssh"
printf "Include ~/.ssh/config.d/passh" > "$bare/.ssh/config"
apply darwin "$bare" "${MAC_TARGETS[@]}"
if printf "$MAC_INCLUDES" | cmp -s - "$bare/.ssh/config"; then
    pass "mac: a lone include without a newline is not duplicated"
else
    fail "mac: config became '$(cat "$bare/.ssh/config")'"
fi

# marshbox identity on the Mac: only the dedicated key, no agent, for every
# marshbox name; trust stays the Mac's own, and the forward is unchanged.
[ ! -e "$mac/.ssh/known_hosts.d" ] && pass "mac: no host-key pin installed" \
    || fail "mac: ~/.ssh/known_hosts.d installed"
for host in marshbox marshbox.local 192.168.1.102 marsh@marshbox.local; do
    cfg=$(ssh -G -F "$resolved" "$host" </dev/null 2>/dev/null)
    ids=$(grep '^identityfile ' <<< "$cfg" | tr '\n' ';')
    if [ "$ids" = "identityfile ~/.ssh/id_ed25519_marshbox;" ] \
        && grep -qx 'identitiesonly yes' <<< "$cfg" \
        && grep -qx 'identityagent none' <<< "$cfg" \
        && ! grep -q '^userknownhostsfile .*known_hosts\.d' <<< "$cfg" \
        && ! grep -qx 'globalknownhostsfile /dev/null' <<< "$cfg" \
        && [ "$(grep '^remoteforward ' <<< "$cfg")" = "$FORWARD" ]; then
        pass "mac: $host uses only the marshbox key, no agent, own trust, one forward"
    else
        fail "mac: $host: $ids $(grep -E '^(identitiesonly|identityagent|userknownhostsfile|globalknownhostsfile|remoteforward) ' <<< "$cfg" | tr '\n' ';')"
    fi
done
for host in serveserve.local github.com marshbox.example; do
    cfg=$(ssh -G -F "$resolved" "$host" </dev/null 2>/dev/null)
    if grep -qE '^(identityagent none|identitiesonly yes|identityfile .*id_ed25519_marshbox)' <<< "$cfg"; then
        fail "mac: marshbox identity leaks to $host"
    else
        pass "mac: $host keeps its identity settings"
    fi
done

# A hand-written marshbox block keeps its trust and connection settings; the
# managed identity options come first and win, and its extra key is offered
# after ours (IdentityFile adds up; it does not replace).
hand="$WORK/hand"
mkdir -p "$hand/.ssh"
cat > "$hand/.ssh/config" <<'EOF'
Host marshbox.local
  HostName 192.168.1.102
  User marsh
  Port 2222
  IdentityFile ~/.ssh/other_key
  IdentitiesOnly no
  IdentityAgent /tmp/some-agent.sock
  UserKnownHostsFile ~/.ssh/known_hosts.marshbox-postinstall
  StrictHostKeyChecking yes
  HostKeyAlias marshbox-reinstalled
EOF
apply darwin "$hand" "${MAC_TARGETS[@]}"
sed "s|~/.ssh/config.d/|$hand/.ssh/config.d/|" "$hand/.ssh/config" > "$WORK/hand_resolved"
cfg=$(ssh -G -F "$WORK/hand_resolved" marshbox.local </dev/null 2>/dev/null)
for want in \
    "identitiesonly yes" "identityagent none" "hostname 192.168.1.102" "user marsh" \
    "port 2222" "userknownhostsfile $HOME/.ssh/known_hosts.marshbox-postinstall" \
    "stricthostkeychecking true" "hostkeyalias marshbox-reinstalled" "$FORWARD"; do
    grep -Fqx -- "$want" <<< "$cfg" && pass "mac+hand-written: has '$want'" \
        || fail "mac+hand-written: lacks '$want'"
done
[ "$(grep -m1 '^identityfile ' <<< "$cfg")" = "identityfile ~/.ssh/id_ed25519_marshbox" ] \
    && pass "mac+hand-written: marshbox key offered first" \
    || fail "mac+hand-written: first identity is '$(grep -m1 '^identityfile ' <<< "$cfg")'"

# The modifier owns only the leading run of managed includes. Each case must
# come out as expected and stay put on a second apply.
check_modify() {
    local label=$1 input=$2 expected=$3 home="$WORK/modify-$RANDOM"
    mkdir -p "$home/.ssh"
    printf "$input" > "$home/.ssh/config"
    apply darwin "$home" "${MAC_TARGETS[@]}"
    if printf "$expected" | cmp -s - "$home/.ssh/config"; then
        apply darwin "$home" "${MAC_TARGETS[@]}"
        printf "$expected" | cmp -s - "$home/.ssh/config" \
            && pass "mac modify: $label" || fail "mac modify: $label changes on re-apply"
    else
        fail "mac modify: $label gave '$(tr '\n' '|' < "$home/.ssh/config")'"
    fi
}
check_modify "both includes already present" \
    "${MAC_INCLUDES}Host a\n" "${MAC_INCLUDES}Host a\n"
check_modify "reordered and duplicated prefix is normalised" \
    "Include ~/.ssh/config.d/marshbox\nInclude ~/.ssh/config.d/passh\n  Include ~/.ssh/config.d/passh  \nHost a\n" \
    "${MAC_INCLUDES}Host a\n"
check_modify "an unrelated include first is kept after the prefix" \
    "Include ~/.ssh/other\nHost a\n" "${MAC_INCLUDES}Include ~/.ssh/other\nHost a\n"
check_modify "a blank line ends the managed run" \
    "Include ~/.ssh/config.d/passh\n\nInclude ~/.ssh/config.d/marshbox\n" \
    "${MAC_INCLUDES}\nInclude ~/.ssh/config.d/marshbox\n"
check_modify "a managed-looking include under a Host is the user's" \
    "Host a\n  Include ~/.ssh/config.d/passh\n" "${MAC_INCLUDES}Host a\n  Include ~/.ssh/config.d/passh\n"

# --- serveserve -------------------------------------------------------------
# Reaches marshbox with its dedicated key and a pinned host key, so sync.sh can
# run from here. It must never carry the Mac's passh forward onward.

serve="$WORK/serveserve"
mkdir -p "$serve/.ssh"
chmod 700 "$serve/.ssh"
# A previous apply under umask 002 left these loose; apply must tighten them.
mkdir -p "$serve/.ssh/config.d" "$serve/.ssh/known_hosts.d"
touch "$serve/.ssh/config.d/marshbox" "$serve/.ssh/known_hosts.d/marshbox"
chmod 775 "$serve/.ssh/config.d" "$serve/.ssh/known_hosts.d"
chmod 664 "$serve/.ssh/config.d/marshbox" "$serve/.ssh/known_hosts.d/marshbox"

IS_SERVER=true apply linux "$serve" .ssh
private_ssh serveserve "$serve"

if printf "Include ~/.ssh/config.d/marshbox\n" | cmp -s - "$serve/.ssh/config"; then
    pass "serveserve: ~/.ssh/config is only the marshbox include"
else
    fail "serveserve: ~/.ssh/config is '$(cat "$serve/.ssh/config")'"
fi
[ ! -e "$serve/.ssh/config.d/passh" ] && pass "serveserve: no passh forward fragment" \
    || fail "serveserve: config.d/passh installed"

pin_fp=$(ssh-keygen -lf "$serve/.ssh/known_hosts.d/marshbox" 2>/dev/null | awk '{print $2, $3, $4}' || true)
[ "$pin_fp" = "SHA256:NPRcirnwuOi11bukahzrKBdvl1xS2++Suy3VAtF1r+A marshbox.local (ED25519)" ] \
    && pass "serveserve: pin holds exactly the verified marshbox host key" \
    || fail "serveserve: pin is '$pin_fp'"
[ "$(grep -c . "$serve/.ssh/known_hosts.d/marshbox" 2>/dev/null)" = 1 ] \
    && pass "serveserve: pin has one key and nothing else" \
    || fail "serveserve: pin has more than one line"

sed "s|~/.ssh/|$serve/.ssh/|" "$serve/.ssh/config" > "$WORK/serve_resolved" 2>/dev/null || true
mb=$(ssh -G -F "$WORK/serve_resolved" marshbox.local </dev/null 2>/dev/null)
for want in \
    "identityfile ~/.ssh/id_ed25519_marshbox" \
    "identitiesonly yes" \
    "identityagent none" \
    "userknownhostsfile $HOME/.ssh/known_hosts.d/marshbox" \
    "globalknownhostsfile /dev/null" \
    "stricthostkeychecking true"; do
    if grep -qx "$want" <<< "$mb"; then
        pass "serveserve: marshbox.local has '$want'"
    else
        fail "serveserve: marshbox.local lacks '$want' (has: $(grep -E "^${want%% *} " <<< "$mb" | tr '\n' ';'))"
    fi
done

# Nothing else changes: other hosts keep ssh's defaults, and nothing forwards.
for host in serveserve.local github.com 192.168.1.102 marshbox; do
    other=$(ssh -G -F "$WORK/serve_resolved" "$host" </dev/null 2>/dev/null)
    if grep -qE '^(identityagent none|identitiesonly yes|userknownhostsfile .*known_hosts.d|globalknownhostsfile /dev/null)' <<< "$other"; then
        fail "serveserve: marshbox settings leak to $host"
    else
        pass "serveserve: $host keeps default identity and trust"
    fi
done
for host in "${FORWARDED[@]}"; do
    got=$(forwards_for "$WORK/serve_resolved" "$host")
    [ -z "$got" ] && pass "serveserve: $host gets no forward" \
        || fail "serveserve: $host forwards: '$got'"
done

# --- any other Linux box (marshbox itself) ----------------------------------

other="$WORK/other-linux"
mkdir -p "$other/.ssh"
cp "$WORK/existing" "$other/.ssh/config"

apply linux "$other" .ssh

if cmp -s "$WORK/existing" "$other/.ssh/config"; then
    pass "other linux: ~/.ssh/config untouched"
else
    fail "other linux: ~/.ssh/config changed"
fi
if [ ! -e "$other/.ssh/config.d" ] && [ ! -e "$other/.ssh/known_hosts.d" ]; then
    pass "other linux: no ssh fragments or pins installed"
else
    fail "other linux: ssh fragments were installed"
fi

echo
if [ "$failures" -ne 0 ]; then
    echo "$failures failure(s)" >&2
    exit 1
fi
echo "all passed"
