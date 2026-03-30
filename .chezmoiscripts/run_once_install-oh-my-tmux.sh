#!/usr/bin/env bash
# Install oh-my-tmux (gpakosz/.tmux) if not already present.
# chezmoi runs this once per machine (tracked by script content hash).
set -euo pipefail

TMUX_DIR="$HOME/.tmux"

if [ -d "$TMUX_DIR" ]; then
    echo "oh-my-tmux already installed at $TMUX_DIR"
    exit 0
fi

echo "Installing oh-my-tmux..."
git clone https://github.com/gpakosz/.tmux.git "$TMUX_DIR"
ln -sf "$TMUX_DIR/.tmux.conf" "$HOME/.tmux.conf"
echo "oh-my-tmux installed. Customizations go in ~/.tmux.conf.local"
