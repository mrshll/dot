#!/usr/bin/env bash
# Regression test: on a Linux box where sudo is unavailable (a fresh machine
# reached by setup/sync.sh), install.sh still installs chezmoi, which lives in
# ~/.local/bin and needs no sudo, and installs nothing that does need sudo.
#
# Runs install.sh against a PATH of stubs only: sudo always fails, curl hands
# back a fake installer that records its arguments. Nothing real is installed.
#
# Usage: tests/install_nosudo_test.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

stubs="$WORK/bin"
mkdir -p "$stubs" "$WORK/home"
for tool in bash sh hostname printf mkdir chmod; do
    ln -s "$(command -v "$tool")" "$stubs/$tool"
done
# install.sh's Linux path is under test, whichever OS runs the test.
printf '#!/bin/sh\necho Linux\n' > "$stubs/uname"
cat > "$stubs/sudo" <<'EOF'
#!/bin/sh
echo "sudo $*" >> "$LOG"
exit 1
EOF
cat > "$stubs/curl" <<'EOF'
#!/bin/sh
echo "curl $*" >> "$LOG"
[ -n "${FAIL_CURL:-}" ] && exit 22
# The installer script: record its arguments and drop a binary where -b says.
echo 'echo "installer $*" >> "$LOG"; mkdir -p "$2"; : > "$2/chezmoi"; chmod +x "$2/chezmoi"'
EOF
chmod +x "$stubs/sudo" "$stubs/curl" "$stubs/uname"

log="$WORK/log"
: > "$log"
env -i HOME="$WORK/home" PATH="$stubs" LOG="$log" \
    "$stubs/bash" "$REPO_DIR/setup/install.sh" </dev/null > "$WORK/out" 2>&1 || {
    cat "$WORK/out" >&2
    echo "FAIL: install.sh exited non-zero" >&2
    exit 1
}

failures=0
if grep -qx "installer -b $WORK/home/.local/bin" "$log"; then
    echo "ok:   chezmoi installer ran into ~/.local/bin without sudo"
else
    echo "FAIL: chezmoi installer did not run; log: $(tr '\n' ';' < "$log")" >&2
    failures=$((failures + 1))
fi
if grep -v '^sudo -n true$' "$log" | grep -q '^sudo'; then
    echo "FAIL: something ran sudo beyond the probe: $(grep '^sudo' "$log" | sort -u | tr '\n' ';')" >&2
    failures=$((failures + 1))
else
    echo "ok:   nothing ran sudo beyond the can_sudo probe"
fi

# A failed download must fail install.sh, not leave sync to find no chezmoi.
rm -rf "$WORK/home"
mkdir -p "$WORK/home"
if env -i HOME="$WORK/home" PATH="$stubs" LOG="$log" FAIL_CURL=1 \
    "$stubs/bash" "$REPO_DIR/setup/install.sh" </dev/null > "$WORK/out" 2>&1; then
    echo "FAIL: install.sh succeeded although the chezmoi download failed" >&2
    failures=$((failures + 1))
else
    echo "ok:   failed chezmoi download fails install.sh"
fi

[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failure(s)" >&2; exit 1; }
