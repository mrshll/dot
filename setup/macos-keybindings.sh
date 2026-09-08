#!/usr/bin/env bash
# Reconcile macOS-level hotkeys with the keyboard ladder.
#
# The app configs (aerospace.toml, kitty.conf, herdr) are chezmoi-managed, but
# Rectangle and the macOS symbolic hotkeys live in binary plists outside
# chezmoi's reach. This script is the manual, idempotent step for those.
#
# Usage: ./setup/macos-keybindings.sh
set -euo pipefail

info() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m==> %s\033[0m\n' "$*"; }

[ "$(uname -s)" = "Darwin" ] || { warn "macOS only — nothing to do."; exit 0; }

# --- Rectangle --------------------------------------------------------------
# Rectangle keeps alt+shift+H / L / F for left half, right half and maximize.
# Those are exactly AeroSpace's alt+shift+hjkl "move window" bindings, and
# Rectangle wins because it registers a global hotkey. Clear the three so the
# OS layer is unambiguous.
#
# Deliberately left alone: Todo mode on ctrl+alt+B (toggle) and ctrl+alt+N
# (reflow), with kitty as the todo app. Those miss the herdr set entirely
# (ctrl+alt+hjkl, ctrl+alt+1..9), so they cost nothing and still work.
#
# Rectangle rewrites its plist on quit, so it has to be stopped first.
if [ -d /Applications/Rectangle.app ]; then
    info "Clearing Rectangle half/maximize shortcuts (Todo mode is kept)..."
    RECTANGLE_WAS_RUNNING=no
    if pgrep -xq Rectangle; then
        RECTANGLE_WAS_RUNNING=yes
        osascript -e 'quit app "Rectangle"' || true
        while pgrep -xq Rectangle; do sleep 0.2; done
    fi

    for action in leftHalf rightHalf maximize; do
        defaults write com.knollsoft.Rectangle "$action" -dict
    done

    if [ "$RECTANGLE_WAS_RUNNING" = yes ]; then
        open -a Rectangle
    fi
else
    info "Rectangle not installed — skipping."
fi

# --- macOS symbolic hotkeys -------------------------------------------------
# Hotkey 34 is enabled on alt+shift+Space. I could not identify what it maps to
# on current macOS (Mission Control is 32, App Windows 33, Spotlight 64/65 —
# all already disabled here), so it reads as vestigial. AeroSpace wants
# alt+shift+Space for the i3 floating/tiling toggle.
#
# To restore it:
#   defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 34 \
#     '<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key>
#      <array><integer>32</integer><integer>49</integer><integer>655360</integer>
#      </array><key>type</key><string>standard</string></dict></dict>'
info "Disabling legacy symbolic hotkey 34 (alt+shift+Space)..."
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 34 \
    '<dict><key>enabled</key><false/></dict>'

# --- Mission Control --------------------------------------------------------
# AeroSpace manages its own workspaces. macOS reordering Spaces by recent use
# desynchronises AeroSpace's model from the real display, so turn it off.
info "Disabling automatic Space rearrangement..."
defaults write com.apple.dock mru-spaces -bool false
killall Dock >/dev/null 2>&1 || true

echo
info "Done."
warn "Symbolic-hotkey changes need a logout/login to take effect."
warn "AeroSpace needs Accessibility permission on first launch:"
warn "  System Settings > Privacy & Security > Accessibility"
