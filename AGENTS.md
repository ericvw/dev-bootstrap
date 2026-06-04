# AGENTS.md

## Commands

```sh
make lint     # shellcheck on bootstrap.sh
make format   # shfmt in-place on bootstrap.sh
```

No automated test suite. Validate changes by running the script directly:

```sh
bash bootstrap.sh --dry-run [--skip-dotfiles] [--skip-packages]
```

## Architecture

`bootstrap.sh` is a single-file bash script (~400 lines) organized with vim
fold markers. `main()` runs seven sequential stages:

1. **Prerequisites** - Installs Xcode CLT (macOS) or apt packages (WSL);
   platform is detected beforehand via top-level code using `is_macos` /
   `is_wsl`
2. **Homebrew** - Installs Homebrew if absent; idempotent
3. **Dotfiles clone** - Clones `$DOTFILES_REPO` into `$DOTFILES_DIR`
4. **Packages** - Reads `$BREW_FORMULAE_FILE` and `brew install`s each line
5. **GCM** - Installs Git Credential Manager via Homebrew cask (macOS only;
   WSL uses GCM from the Windows host)
6. **Dotfiles install** - Runs `$DOTFILES_DIR/install.sh` if present
7. **Configure** - Sets fish as default shell via `sudo chsh`; drops a
   sudoers drop-in on WSL to preserve `EDITOR` and `VISUAL`

**Helper layer** (defined before stages):
- `run` / `run_sh` / `run_eval` - wrap every shell command; respect `--dry-run`
- `log` / `warn` / `err` - colored output
- `is_macos` / `is_wsl` - platform predicates
- `need_sudo` - caches sudo credentials; short-circuits under `--dry-run`
- `sudoers_write` - validates content in a temp file before placing in
  `/etc/sudoers.d`
- `have` - command existence check

**Key env vars** (can be set before running):
- `DOTFILES_REPO` (default: `https://github.com/ericvw/dotfiles`)
- `DOTFILES_DIR` (default: `$HOME/.dotfiles`)
- `BREW_FORMULAE_FILE` (default: `$DOTFILES_DIR/brew-formulae.txt`)

The script is intentionally idempotent: each stage checks whether its work is
already done before acting.

## Windows

`git-install.inf` is an InnoSetup response file consumed by the Git for
Windows installer via `/LOADINF`. It captures install-time options
(components, editor, PATH integration, CRLF handling, credential manager,
symlinks) verified against the current Windows registry. To regenerate from
scratch: run the Git installer interactively with `/SAVEINF=git-install.inf`.
