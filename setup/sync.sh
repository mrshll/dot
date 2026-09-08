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
# Add machines here. Format: user@host. A remote that is this machine is
# skipped, so the script can run from any listed host.
REMOTES=(
    "serveserve.local"
)

is_local_host() {
    local host=${1#*@} short_host short_local
    short_host=$(printf '%s' "${host%%.*}" | tr '[:upper:]' '[:lower:]')
    short_local=$(hostname -s 2>/dev/null || hostname)
    short_local=$(printf '%s' "${short_local%%.*}" | tr '[:upper:]' '[:lower:]')
    [ "$short_host" = "$short_local" ]
}

# Runs on each remote. "collect" commits and pushes edits made there, so a
# change applied on a remote is never left behind; "apply" pulls and applies.
run_remote() {
    local remote=$1 mode=$2
    ssh -t "$remote" bash -s -- "$REPO_REMOTE" "$mode" <<'REMOTE_SCRIPT'
        set -euo pipefail
        REPO_REMOTE="$1"
        MODE="$2"
        REPO_DIR="$HOME/workspace/dot"

        if [ ! -d "$REPO_DIR" ]; then
            [ "$MODE" = apply ] || exit 0
            echo "  Cloning..."
            mkdir -p "$(dirname "$REPO_DIR")"
            git clone "$REPO_REMOTE" "$REPO_DIR"
        fi

        if [ "$MODE" = collect ]; then
            if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
                echo "  Local changes detected — committing..."
                git -C "$REPO_DIR" add -A
                git -C "$REPO_DIR" commit -m "sync: $(date '+%Y-%m-%d %H:%M') ($(hostname -s 2>/dev/null || hostname))"
            fi
            if [ -n "$(git -C "$REPO_DIR" log --oneline '@{upstream}..HEAD' 2>/dev/null)" ]; then
                echo "  Pushing..."
                git -C "$REPO_DIR" pull --rebase
                git -C "$REPO_DIR" push
            fi
            exit 0
        fi

        echo "  Pulling..."
        git -C "$REPO_DIR" pull --ff-only

        echo "  Checking packages..."
        "$REPO_DIR/setup/install.sh"

        CHEZMOI=""
        if command -v chezmoi >/dev/null 2>&1; then
            CHEZMOI="chezmoi"
        elif [ -x "$HOME/.local/bin/chezmoi" ]; then
            CHEZMOI="$HOME/.local/bin/chezmoi"
        elif [ -x /opt/homebrew/bin/chezmoi ]; then
            CHEZMOI=/opt/homebrew/bin/chezmoi
        else
            echo "  chezmoi not found — run setup/install.sh on this machine first"
            exit 0
        fi

        SRC="$($CHEZMOI source-path 2>/dev/null || true)"
        if [ -n "$SRC" ] && [ -d "$SRC" ]; then
            $CHEZMOI apply
        else
            $CHEZMOI init --source="$REPO_DIR" --apply
        fi
        echo "  Applied."
REMOTE_SCRIPT
}

REACHABLE=()
for remote in "${REMOTES[@]}"; do
    if is_local_host "$remote"; then
        info "Skipping $remote (this machine)."
        continue
    fi
    REACHABLE+=("$remote")
done

# --- collect remote edits first ---------------------------------------------
# So the local pull below sees them and every machine ends on the same commit.

for remote in "${REACHABLE[@]}"; do
    echo
    info "Collecting edits from $remote..."
    run_remote "$remote" collect
done

# --- local ------------------------------------------------------------------

cd "$REPO_DIR"

# Push any uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    info "Local changes detected — committing..."
    git add -A
    git commit -m "sync: $(date '+%Y-%m-%d %H:%M') ($(hostname -s 2>/dev/null || hostname))"
fi

info "Pulling latest..."
git pull --rebase

info "Checking packages..."
if [ "$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    brew bundle check --file="$REPO_DIR/Brewfile" &>/dev/null || brew bundle install --file="$REPO_DIR/Brewfile"
else
    "$REPO_DIR/setup/install.sh"
fi

info "Pushing to origin..."
git push

info "Applying locally..."
if chezmoi source-path &>/dev/null; then
    chezmoi apply
else
    chezmoi init --source="$REPO_DIR" --apply
fi

# --- apply on remotes -------------------------------------------------------

for remote in "${REACHABLE[@]}"; do
    echo
    info "Syncing $remote..."
    run_remote "$remote" apply
    info "$remote done."
done

echo
info "All machines synced."
