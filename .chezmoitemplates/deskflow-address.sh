# home_address FILE: the first line of FILE, whitespace stripped, if it is a
# private (RFC 1918) IPv4 address; otherwise 127.0.0.1. Deskflow is for the
# home LAN only, so a Tailscale (100.64/10) or public address, a hostname,
# 0.0.0.0, a missing file or junk all fall back to loopback, which connects
# to and listens for nothing on the network.
home_address() {
    a=$(head -n 1 "$1" 2>/dev/null | tr -d '[:space:]') || a=
    o='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])'
    if printf '%s\n' "$a" | grep -Eqx "(10(\\.$o){3}|172\\.(1[6-9]|2[0-9]|3[01])(\\.$o){2}|192\\.168(\\.$o){2})"; then
        printf '%s\n' "$a"
    else
        printf '127.0.0.1\n'
    fi
}
