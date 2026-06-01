#!/usr/bin/env bash
# vim: foldmethod=marker

set -euo pipefail

# Configuration {{{
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/ericvw/dotfiles}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
BREW_FORMULAE_FILE="${BREW_FORMULAE_FILE:-$DOTFILES_DIR/brew-formulae.txt}"
# }}}

# Command-line parsing {{{
ASSUME_YES=false
DRY_RUN=false
SKIP_DOTFILES=false
SKIP_PACKAGES=false

usage() {
    cat << 'EOF'
Usage: bash bootstrap.sh [options]

Options:
  --yes            Non-interactive; assume "yes" for prompts
  --dry-run        Print actions without executing them
  --skip-dotfiles  Don't clone/install dotfiles
  --skip-packages  Don't install packages (brew install)
  -h, --help       Show help

Env overrides:
  DOTFILES_REPO, DOTFILES_DIR, BREW_FORMULAE_FILE
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes)
            ASSUME_YES=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-dotfiles)
            SKIP_DOTFILES=true
            shift
            ;;
        --skip-packages)
            SKIP_PACKAGES=true
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown arg: $1"
            usage
            exit 1
            ;;
    esac
done
# }}}

# Helpers {{{
log() { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m!!\033[0m %s\n" "$*"; }
err() { printf "\033[1;31mxx\033[0m %s\n" "$*"; }

run() {
    if $DRY_RUN; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

run_eval() {
    if $DRY_RUN; then
        echo "[dry-run] $*"
    else
        eval "$*"
    fi
}

run_sh() {
    if $DRY_RUN; then
        echo "[dry-run] $*"
    else
        bash -c "$1"
    fi
}

confirm() {
    local prompt="${1:-Continue?}"
    $ASSUME_YES && return 0
    read -r -p "$prompt [y/N] " ans
    [[ "${ans:-}" =~ ^[Yy]$ ]]
}

have() { command -v "$1" > /dev/null 2>&1; }

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }

is_wsl() {
    # Works for WSL1/WSL2
    grep -qiE "(microsoft|wsl)" /proc/version 2> /dev/null
}

need_sudo() {
    if $DRY_RUN; then return 0; fi
    if have sudo; then
        sudo -n true > /dev/null 2>&1 || sudo -v
    else
        err "sudo not found; install it or run as a user with privileges."
        exit 1
    fi
}

sudoers_write() {
    local dest="$1"
    local content="$2"
    if $DRY_RUN; then
        echo "[dry-run] sudoers_write $dest: $content"
        return 0
    fi
    local tmp
    tmp="$(mktemp)"
    printf '%s\n' "$content" > "$tmp"
    if ! visudo -cf "$tmp" > /dev/null 2>&1; then
        rm -f "$tmp"
        err "sudoers syntax check failed for: $dest"
        exit 1
    fi
    sudo install -m 0440 "$tmp" "$dest"
    rm -f "$tmp"
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
    if ! xcode-select -p > /dev/null 2>&1; then
        warn "Xcode Command Line Tools not found."
        if confirm "Install Xcode Command Line Tools now?"; then
            # This opens a GUI prompt; user must complete it.
            run_sh 'xcode-select --install || true'
            warn "If installation prompts appeared, complete them, then re-run the script."
        else
            warn "Skipping Xcode CLT install. Brew install may fail."
        fi
    fi
}

install_wsl_prereqs() {
    log "Installing WSL prerequisites (Ubuntu/Debian)..."
    need_sudo
    run sudo apt-get update -y
    run sudo apt-get install -y build-essential curl file git procps ca-certificates
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
            # shellcheck disable=SC2016
            run_eval 'eval "$(/opt/homebrew/bin/brew shellenv)"'
        fi
    else
        if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
            # shellcheck disable=SC2016
            run_eval 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
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
    # shellcheck disable=SC2016
    run_sh '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'

    brew_shellenv_eval

    if ! have brew; then
        err "brew still not found after install."
        exit 1
    fi

    log "Homebrew installed: $(brew --version | head -n 1)"
}
# }}}

# Bootstrap dotfiles {{{
clone_dotfiles() {
    if $SKIP_DOTFILES; then
        warn "Skipping dotfiles."
        return 0
    fi

    log "Setting up dotfiles in: $DOTFILES_DIR"

    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        log "Dotfiles repo already exists."
    else
        log "Cloning dotfiles repo..."
        run git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
    fi
}

install_dotfiles() {
    if $SKIP_DOTFILES; then return 0; fi

    if [[ -x "$DOTFILES_DIR/install.sh" ]]; then
        log "Running dotfiles install script..."
        run "$DOTFILES_DIR/install.sh"
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

    if [[ ! -f "$BREW_FORMULAE_FILE" ]]; then
        warn "No formula list found at $BREW_FORMULAE_FILE; skipping."
        return 0
    fi

    local -a args=()
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] && args+=("$line")
    done < "$BREW_FORMULAE_FILE"

    if [[ "${#args[@]}" -eq 0 ]]; then
        warn "Formula list is empty: $BREW_FORMULAE_FILE"
        return 0
    fi

    log "Installing formulae from $BREW_FORMULAE_FILE"
    run brew install "${args[@]}"
}
# }}}

# Configure sudoers {{{
configure_sudoers() {
    if [[ "$PLATFORM" != "wsl" ]]; then return 0; fi

    local dest="/etc/sudoers.d/editor-env-keep"
    if [[ -f "$dest" ]]; then
        log "sudoers editor config already in place."
        return 0
    fi

    need_sudo
    log "Writing $dest..."
    sudoers_write "$dest" 'Defaults env_keep += "EDITOR VISUAL"'
}
# }}}

# Configure environment {{{
configure_environment() {
    set_default_shell_to_fish
    configure_sudoers
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
        run_sh "echo '$shell' | sudo tee -a /etc/shells"
    fi

    run chsh -s "$shell"
}
# }}}

# Main {{{
main() {
    log "Detected platform: $PLATFORM"

    install_platform_prereqs
    install_brew
    clone_dotfiles
    install_packages
    install_dotfiles
    configure_environment

    log "Bootstrap complete."
    warn "Open a new terminal (or source your rc file) so PATH changes take effect."
}

main
# }}}
