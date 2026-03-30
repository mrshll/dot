#!/usr/bin/env bash
# Install chezmoi and core packages.
# Works on macOS (Homebrew) and Linux (apt + fallbacks).
# Safe to run repeatedly — skips already-installed packages.
set -euo pipefail

# --- helpers ----------------------------------------------------------------

info()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m==> %s\033[0m\n' "$*"; }
err()   { printf '\033[1;31m==> %s\033[0m\n' "$*" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

OS="$(uname -s)"

# --- platform installers ----------------------------------------------------

brew_install() {
    if ! command_exists brew; then
        err "Homebrew not found — install it first: https://brew.sh"
        exit 1
    fi
    for pkg in "$@"; do
        if brew list "$pkg" &>/dev/null; then
            info "$pkg already installed (brew)"
        else
            info "Installing $pkg via brew..."
            brew install "$pkg"
        fi
    done
}

apt_install() {
    for pkg in "$@"; do
        if dpkg -s "$pkg" &>/dev/null 2>&1; then
            info "$pkg already installed (apt)"
        else
            info "Installing $pkg via apt..."
            sudo apt-get update -qq
            sudo apt-get install -y -qq "$pkg"
        fi
    done
}

# --- core packages ----------------------------------------------------------
#
# Add packages here. Format:
#   install <command_name> <brew_name> <apt_name|CUSTOM>
#
# Use CUSTOM for packages that need special install logic on Linux.

install_pkg() {
    local cmd="$1" brew_name="$2" apt_name="$3"

    if command_exists "$cmd"; then
        info "$cmd already installed"
        return
    fi

    case "$OS" in
        Darwin) brew_install "$brew_name" ;;
        Linux)
            if [ "$apt_name" = "CUSTOM" ]; then
                "install_${cmd}_linux"
            else
                apt_install "$apt_name"
            fi
            ;;
    esac
}

# --- custom Linux installers for packages not in default apt ----------------

install_eza_linux() {
    # eza has an official apt repo
    if ! command_exists eza; then
        info "Installing eza via official apt repo..."
        sudo mkdir -p /etc/apt/keyrings
        wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
        sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
        sudo apt-get update -qq
        sudo apt-get install -y -qq eza
    fi
}

install_bat_linux() {
    # Ubuntu ships batcat; we alias it in fish
    if command_exists batcat; then
        info "batcat already installed (Ubuntu names it batcat)"
        return
    fi
    apt_install bat
}

install_chezmoi_linux() {
    info "Installing chezmoi via official installer..."
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"
}

# --- main -------------------------------------------------------------------

info "Setting up on $OS ($(hostname))"
echo

#              command   brew-name    apt-name
install_pkg    git       git          git
install_pkg    fish      fish         fish
install_pkg    nvim      neovim       neovim
install_pkg    tmux      tmux         tmux
install_pkg    eza       eza          CUSTOM
install_pkg    bat       bat          CUSTOM
install_pkg    jq        jq           jq
install_pkg    http      httpie       httpie
install_pkg    fzf       fzf          fzf
install_pkg    gh        gh           gh
install_pkg    btop      btop         btop
install_pkg    chezmoi   chezmoi      CUSTOM

# 1Password CLI — optional, just advise
if ! command_exists op; then
    echo
    warn "1Password CLI (op) not found — optional, for secret auto-provisioning:"
    case "$OS" in
        Darwin) warn "  brew install --cask 1password-cli" ;;
        Linux)  warn "  https://developer.1password.com/docs/cli/get-started/#install" ;;
    esac
fi

echo
info "All tools installed. Next steps:"
info "  1. Run ./setup/secrets.sh to provision pond secrets"
info "  2. Run ./setup/apply.sh to apply dotfiles"
