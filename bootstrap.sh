#!/usr/bin/env bash
# vim: foldmethod=marker

set -euo pipefail

# Configuration {{{
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/ericvw/dotfiles}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
BREWFILE_PATH="${BREWFILE_PATH:-$DOTFILES_DIR/Brewfile}"
# }}}

# Command-line parsing {{{
ASSUME_YES=false
DRY_RUN=false
SKIP_DOTFILES=false
SKIP_PACKAGES=false
SKIP_SETTINGS=false

usage() {
    cat <<'EOF'
Usage: bash bootstrap.sh [options]

Options:
  --yes            Non-interactive; assume "yes" for prompts
  --dry-run        Print actions without executing them
  --skip-dotfiles  Don't clone/install dotfiles
  --skip-packages  Don't install packages (brew bundle)
  --skip-settings  Don't apply OS settings (macOS defaults / WSL tweaks)
  -h, --help       Show help

Env overrides:
  DOTFILES_REPO, DOTFILES_DIR, BREWFILE_PATH
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes) ASSUME_YES=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --skip-dotfiles) SKIP_DOTFILES=true; shift ;;
        --skip-packages) SKIP_PACKAGES=true; shift ;;
        --skip-settings) SKIP_SETTINGS=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown arg: $1"; usage; exit 1 ;;
    esac
done
# }}}

# Helpers {{{
log()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m!!\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31mxx\033[0m %s\n" "$*"; }

run() {
    if $DRY_RUN; then
        echo "[dry-run] $*"
    else
        eval "$@"
    fi
}

confirm() {
    local prompt="${1:-Continue?}"
    $ASSUME_YES && return 0
    read -r -p "$prompt [y/N] " ans
    [[ "${ans:-}" =~ ^[Yy]$ ]]
}

have() { command -v "$1" >/dev/null 2>&1; }

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }

is_wsl() {
    # Works for WSL1/WSL2
    grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null
}

need_sudo() {
    if have sudo; then
        sudo -n true >/dev/null 2>&1 || true
    else
        err "sudo not found; install it or run as a user with privileges."
        exit 1
    fi
}
# }}}

# Platform detection {{{
PLATFORM="unknown"
if is_macos; then
    PLATFORM="macos"
elif is_wsl; then
    PLATFORM="wsl"
else
    warn "Unknown platform. This script targets macOS and WSL (Ubuntu/Debian)."
    PLATFORM="linux"
fi
# }}}

# Bootstrap OS packages for Homebrew {{{
install_macos_prereqs() {
    log "Checking macOS prerequisites..."
    if ! xcode-select -p >/dev/null 2>&1; then
        warn "Xcode Command Line Tools not found."
        if confirm "Install Xcode Command Line Tools now?"; then
            # This opens a GUI prompt; user must complete it.
            run "xcode-select --install || true"
            warn "If installation prompts appeared, complete them, then re-run the script."
        else
            warn "Skipping Xcode CLT install. Brew install may fail."
        fi
    fi
}

install_wsl_prereqs() {
    log "Installing WSL prerequisites (Ubuntu/Debian)..."
    need_sudo
    run "sudo apt-get update -y"
    run "sudo apt-get install -y build-essential curl file git procps ca-certificates"
}

install_platform_prereqs() {
    case "$PLATFORM" in
        macos) install_macos_prereqs ;;
        wsl) install_wsl_prereqs ;;
        *) warn "Skipping platform-specific prerequisites for: $PLATFORM" ;;
    esac
}
# }}}

# Bootstrap Homebrew {{{
brew_shellenv_eval() {
    # Ensure brew is on PATH for current process.
    if is_macos; then
        if [[ -x /opt/homebrew/bin/brew ]]; then
            run 'eval "$(/opt/homebrew/bin/brew shellenv)"'
        fi
    else
        if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
            run 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
        fi
    fi
}

install_brew() {
    # If brew is not on PATH, attempt to add it to PATH in case it is already installed.
    if ! have brew; then
        brew_shellenv_eval
    fi

    if have brew; then
        log "Homebrew already installed."
        return 0
    fi

    log "Installing Homebrew..."
    if ! have curl; then
        err "curl is required to install Homebrew."
        exit 1
    fi

    # Official Homebrew installer.
    run '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'

    brew_shellenv_eval

    if ! have brew; then
        err "brew still not found after install."
        exit 1
    fi

    log "Homebrew installed: $(brew --version | head -n 1)"
}
# }}}

# Bootstrap dotfiles {{{
clone_or_update_dotfiles() {
    if $SKIP_DOTFILES; then
        warn "Skipping dotfiles."
        return 0
    fi

    log "Setting up dotfiles in: $DOTFILES_DIR"

    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        log "Dotfiles repo already exists."
    else
        log "Cloning dotfiles repo..."
        run "git clone '$DOTFILES_REPO' '$DOTFILES_DIR'"
    fi
}

install_dotfiles() {
    if $SKIP_DOTFILES; then return 0; fi

    if [[ -x "$DOTFILES_DIR/install.sh" ]]; then
        log "Running dotfiles install script..."
        run "'$DOTFILES_DIR/install.sh'"
        return 0
    fi

    warn "No install.sh found."
}
# }}}

# Bootstrap packages {{{
install_packages() {
    if $SKIP_PACKAGES; then
        warn "Skipping packages."
        return 0
    fi

    if [[ -f "$BREWFILE_PATH" ]]; then
        log "Installing packages from Brewfile: $BREWFILE_PATH"
        run "brew update"
        run "brew bundle --file '$BREWFILE_PATH'"
    else
        warn "No Brewfile found at $BREWFILE_PATH; skipping brew bundle."
        warn "Tip: put a Brewfile in your dotfiles repo and set BREWFILE_PATH if needed."
    fi
}
# }}}

# Bootstrap default shell {{{
user_default_shell() {
    case "$PLATFORM" in
        macos)
            dscl . -read ~/ UserShell | sed 's/UserShell: //'
            ;;
        *)
            awk -F: -v u="$USER" '$1==u {print $NF; exit}' /etc/passwd
            ;;
    esac
}

set_default_shell_to_fish() {
    local shell=
    shell="$(brew --prefix)/bin/fish"
    if [[ ! -x "$shell" ]]; then
        warn "fish is not installed; skipping applying default shell."
        return 0
    fi

    # Already set?
    if [[ $(user_default_shell) == "$shell" ]]; then
        log "Default shell already set to fish: $shell"
        return 0
    fi

    # Append to list of permitted shells if it doesn't exist.
    if ! grep -qxF "$shell" /etc/shells; then
        log "Adding fish to /etc/shells (requires sudo)..."
        run "echo $shell | sudo tee -a /etc/shells"
    fi

    run "chsh -s '$shell'"
}
# }}}

# Bootstrap OS settings {{{
apply_macos_defaults() {
    log "Applying a few macOS defaults (safe-ish)…"
    # These are examples; tailor to your preferences.
    run "defaults write NSGlobalDomain AppleShowAllExtensions -bool true"
    run "defaults write com.apple.finder AppleShowAllFiles -bool true"
    run "defaults write com.apple.finder ShowPathbar -bool true"
    run "defaults write com.apple.finder ShowStatusBar -bool true"
    # run "defaults write com.apple.dock autohide -bool true"
    # run "defaults write NSGlobalDomain KeyRepeat -int 2"
    # run "defaults write NSGlobalDomain InitialKeyRepeat -int 15"
    run "killall Finder >/dev/null 2>&1 || true"
    run "killall Dock >/dev/null 2>&1 || true"
}

apply_wsl_tweaks() {
    log "Applying a few WSL tweaks…"
    log "Nothing to apply."
}

apply_settings() {
    if $SKIP_SETTINGS; then
        warn "Skipping settings."
        return 0
    fi

    case "$PLATFORM" in
        macos) apply_macos_defaults ;;
        wsl) apply_wsl_tweaks ;;
        *) warn "No settings defined for platform: $PLATFORM" ;;
    esac
}
# }}}

# Main {{{
main() {
    log "Detected platform: $PLATFORM"

    install_platform_prereqs
    install_brew
    clone_or_update_dotfiles
    install_packages
    install_dotfiles
    set_default_shell_to_fish
    # apply_settings

    log "Bootstrap complete."
    warn "Open a new terminal (or source your rc file) so PATH changes take effect."
}

main
# }}}
