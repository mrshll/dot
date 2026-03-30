#!/usr/bin/env bash
# Install chezmoi and optional dependencies.
# Works on macOS (Homebrew) and Linux (apt + curl fallback).
set -euo pipefail

# --- helpers ----------------------------------------------------------------

info()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m==> %s\033[0m\n' "$*"; }
err()   { printf '\033[1;31m==> %s\033[0m\n' "$*" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

OS="$(uname -s)"

# --- platform package helpers -----------------------------------------------

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

# --- chezmoi ----------------------------------------------------------------

install_chezmoi() {
    if command_exists chezmoi; then
        info "chezmoi already installed: $(chezmoi --version)"
        return
    fi

    case "$OS" in
        Darwin) brew_install chezmoi ;;
        Linux)
            if command_exists apt-get; then
                # chezmoi provides a one-liner that works everywhere
                info "Installing chezmoi via official installer..."
                sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
                export PATH="$HOME/.local/bin:$PATH"
            else
                err "Unsupported Linux package manager — install chezmoi manually"
                exit 1
            fi
            ;;
        *) err "Unsupported OS: $OS"; exit 1 ;;
    esac

    info "chezmoi installed: $(chezmoi --version)"
}

# --- fish -------------------------------------------------------------------

install_fish() {
    if command_exists fish; then
        info "fish already installed: $(fish --version)"
        return
    fi

    case "$OS" in
        Darwin) brew_install fish ;;
        Linux)  apt_install fish ;;
    esac
}

# --- neovim -----------------------------------------------------------------

install_neovim() {
    if command_exists nvim; then
        info "nvim already installed: $(nvim --version | head -1)"
        return
    fi

    case "$OS" in
        Darwin) brew_install neovim ;;
        Linux)
            # Ubuntu's apt neovim is often outdated; use the PPA or appimage
            if command_exists apt-get; then
                info "Installing neovim via apt (consider PPA for latest)..."
                apt_install neovim
            fi
            ;;
    esac
}

# --- btop -------------------------------------------------------------------

install_btop() {
    if command_exists btop; then
        info "btop already installed"
        return
    fi

    case "$OS" in
        Darwin) brew_install btop ;;
        Linux)  apt_install btop ;;
    esac
}

# --- tmux -------------------------------------------------------------------

install_tmux() {
    if command_exists tmux; then
        info "tmux already installed: $(tmux -V)"
        return
    fi

    case "$OS" in
        Darwin) brew_install tmux ;;
        Linux)  apt_install tmux ;;
    esac
}

# --- git ---------------------------------------------------------------------

install_git() {
    if command_exists git; then
        info "git already installed: $(git --version)"
        return
    fi

    case "$OS" in
        Darwin) brew_install git ;;
        Linux)  apt_install git ;;
    esac
}

# --- 1Password CLI (optional) -----------------------------------------------

install_op() {
    if command_exists op; then
        info "1Password CLI already installed: $(op --version)"
        return
    fi

    warn "1Password CLI (op) not found."
    warn "Install manually if you want secret auto-provisioning:"
    case "$OS" in
        Darwin) warn "  brew install --cask 1password-cli" ;;
        Linux)  warn "  https://developer.1password.com/docs/cli/get-started/#install" ;;
    esac
}

# --- main -------------------------------------------------------------------

info "Setting up on $OS ($(hostname))"
echo

install_git
install_chezmoi
install_fish
install_neovim
install_btop
install_tmux
install_op

echo
info "All tools installed. Next steps:"
info "  1. Run ./setup/secrets.sh to provision pond secrets"
info "  2. Run ./setup/apply.sh to apply dotfiles"
