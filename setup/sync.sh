#!/usr/bin/env bash
# Sync dotfiles locally and on all remotes.
# Usage: ./setup/sync.sh
set -euo pipefail

info()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m==> %s\033[0m\n' "$*"; }
err()   { printf '\033[1;31m==> %s\033[0m\n' "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_REMOTE="git@github.com:mrshll/dot.git"

# --- remotes ----------------------------------------------------------------
# Add machines here. Format: user@host
REMOTES=(
    "serveserve.local"
)

# --- local ------------------------------------------------------------------

cd "$REPO_DIR"

# Push any uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    info "Local changes detected — committing..."
    git add -A
    git commit -m "sync: $(date '+%Y-%m-%d %H:%M')"
fi

info "Pushing to origin..."
git push

info "Applying locally..."
chezmoi apply

# --- remotes ----------------------------------------------------------------

for remote in "${REMOTES[@]}"; do
    echo
    info "Syncing $remote..."

    ssh "$remote" bash -s -- "$REPO_REMOTE" <<'REMOTE_SCRIPT'
        set -euo pipefail
        REPO_REMOTE="$1"
        REPO_DIR="$HOME/workspace/dot"

        if [ ! -d "$REPO_DIR" ]; then
            echo "  Cloning..."
            mkdir -p "$(dirname "$REPO_DIR")"
            git clone "$REPO_REMOTE" "$REPO_DIR"
        else
            echo "  Pulling..."
            git -C "$REPO_DIR" pull --ff-only
        fi

        if command -v chezmoi >/dev/null 2>&1; then
            chezmoi apply --source="$REPO_DIR"
            echo "  Applied."
        elif [ -x "$HOME/.local/bin/chezmoi" ]; then
            "$HOME/.local/bin/chezmoi" apply --source="$REPO_DIR"
            echo "  Applied."
        else
            echo "  chezmoi not found — run setup/install.sh on this machine first"
        fi
REMOTE_SCRIPT

    info "$remote done."
done

echo
info "All machines synced."
