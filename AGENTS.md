# AGENTS.md

## Commands

```sh
make lint     # shellcheck on bootstrap.sh
make format   # shfmt in-place on bootstrap.sh
```

No automated test suite. Validate changes by running the script directly:

```sh
bash bootstrap.sh --dry-run [--force] [--yes] [--skip-dotfiles] [--skip-packages]
```

## Architecture

`bootstrap.sh` is a single-file bash script (~330 lines) organized with vim
fold markers into five sequential stages:

1. **Prerequisites** - Platform detection (`is_macos`, `is_wsl`) then installs
   Xcode CLT (macOS) or apt packages (WSL)
2. **Homebrew** - Installs Homebrew if absent; idempotent
3. **Dotfiles** - Clones `$DOTFILES_REPO` into `$DOTFILES_DIR` then runs
   `stow` to link; `--force` backs up collisions before linking
4. **Packages** - Reads `$BREW_FORMULAE_FILE` and `brew install`s each line
5. **Shell** - Adds fish to `/etc/shells` and runs `chsh`

**Helper layer** (defined before stages):
- `run` / `run_sh` / `run_eval` - wrap every shell command; respect `--dry-run`
- `log` / `warn` / `err` - colored output
- `confirm` - interactive prompt; short-circuits under `--yes`
- `have` - command existence check

**Key env vars** (can be set before running):
- `DOTFILES_REPO` (default: `https://github.com/ericvw/dotfiles`)
- `DOTFILES_DIR` (default: `$HOME/.dotfiles`)
- `BREW_FORMULAE_FILE` (default: `$DOTFILES_DIR/brew-formulae.txt`)

The script is intentionally idempotent: each stage checks whether its work is
already done before acting.
