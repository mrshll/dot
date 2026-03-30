#!/usr/bin/env bash
# Initialize chezmoi with this repo and apply dotfiles.
# Safe to run repeatedly — chezmoi is idempotent.
#
# Usage:
#   First time:   ./setup/apply.sh
#   After cloning: ./setup/apply.sh
#   Update:        ./setup/apply.sh
set -euo pipefail

info()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m==> %s\033[0m\n' "$*"; }
err()   { printf '\033[1;31m==> %s\033[0m\n' "$*" >&2; }

# --- locate chezmoi ---------------------------------------------------------

if command -v chezmoi >/dev/null 2>&1; then
    CHEZMOI="chezmoi"
elif [ -x "$HOME/.local/bin/chezmoi" ]; then
    CHEZMOI="$HOME/.local/bin/chezmoi"
else
    err "chezmoi not found — run ./setup/install.sh first"
    exit 1
fi

# --- resolve repo dir -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

info "Source: $REPO_DIR"

# --- init or update ---------------------------------------------------------

CHEZMOI_SOURCE="$($CHEZMOI source-path 2>/dev/null || true)"

if [ -z "$CHEZMOI_SOURCE" ] || [ ! -d "$CHEZMOI_SOURCE" ]; then
    info "Initializing chezmoi with $REPO_DIR"
    $CHEZMOI init --source="$REPO_DIR" --apply
else
    if [ "$(cd "$CHEZMOI_SOURCE" && pwd)" != "$REPO_DIR" ]; then
        warn "chezmoi source is $CHEZMOI_SOURCE (expected $REPO_DIR)"
        warn "Re-initializing..."
        $CHEZMOI init --source="$REPO_DIR" --apply
    else
        info "Applying dotfiles..."
        $CHEZMOI apply
    fi
fi

# --- summary ----------------------------------------------------------------

echo
info "Done. Managed files:"
$CHEZMOI managed | while read -r f; do
    printf "  %s\n" "$f"
done

# --- reminders --------------------------------------------------------------

echo
if [ ! -f "$HOME/.config/pond/.env" ]; then
    warn "Pond secrets not provisioned yet — run ./setup/secrets.sh"
fi

TMUX_CONF="$REPO_DIR/dot_config/tmux/tmux.conf"
if grep -q "Placeholder" "$TMUX_CONF" 2>/dev/null; then
    warn "tmux.conf is still a placeholder — pull from serveserve.local:"
    warn "  scp serveserve.local:.tmux.conf $TMUX_CONF"
fi
