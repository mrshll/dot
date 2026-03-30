#!/usr/bin/env bash
# Pull configs from serveserve.local that aren't yet in the repo.
# Run from any machine that has SSH access to the server.
set -euo pipefail

info()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m==> %s\033[0m\n' "$*"; }

SERVER="${POND_SERVER_HOST:-serveserve.local}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- tmux (.tmux.conf.local for oh-my-tmux) --------------------------------

info "Checking for tmux config on $SERVER..."

if ssh "$SERVER" "test -f ~/.tmux.conf.local" 2>/dev/null; then
    info "Found .tmux.conf.local on $SERVER — pulling..."
    scp "$SERVER:~/.tmux.conf.local" "$REPO_DIR/dot_tmux.conf.local"
    info "Merged server's .tmux.conf.local into repo"
elif ssh "$SERVER" "test -f ~/.tmux.conf" 2>/dev/null; then
    warn "Found plain .tmux.conf on $SERVER (not oh-my-tmux)"
    warn "Saving to /tmp/server-tmux.conf for reference"
    scp "$SERVER:~/.tmux.conf" "/tmp/server-tmux.conf"
    warn "Review it and migrate settings to dot_tmux.conf.local"
else
    warn "No tmux config found on $SERVER"
fi

# --- fish (server variant) --------------------------------------------------

info "Pulling fish config from $SERVER for reference..."
mkdir -p "/tmp/dot-server-fish"
scp "$SERVER:~/.config/fish/config.fish" "/tmp/dot-server-fish/config.fish" 2>/dev/null || true

if [ -f "/tmp/dot-server-fish/config.fish" ]; then
    info "Server fish config saved to /tmp/dot-server-fish/config.fish"
    info "Review it and update dot_config/fish/config.fish.tmpl if needed"
    echo "--- server config.fish ---"
    cat "/tmp/dot-server-fish/config.fish"
    echo "--- end ---"
fi

echo
info "Done. Review changes and commit:"
info "  cd $REPO_DIR && git diff"
