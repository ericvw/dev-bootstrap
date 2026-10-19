# AGENTS.md

## Commands

```sh
make lint     # shellcheck on every *.sh file
make format   # shfmt in-place on every *.sh file
```

No automated test suite. Validate changes by running the script directly:

```sh
bash bootstrap.sh --dry-run [--skip-dotfiles] [--skip-packages]
```

Read [ARCHITECTURE.md](ARCHITECTURE.md) before making changes that affect
bootstrap flow, platform behavior, repository boundaries, or dotfiles
integration.

## Constraints

- `bootstrap.sh` must run under the Bash shipped with stock macOS (3.2); no
  Bash 4+ features.
- Every state-changing operation must honor `--dry-run`: use `run`,
  `run_sh`, or `run_eval` for ordinary commands and `sudoers_write` for
  sudoers changes; any other direct mutation needs its own dry-run check
  (see [Architectural Invariants](ARCHITECTURE.md#architectural-invariants)).
- Call `need_sudo` before the first privileged command in a stage, not
  inline with it.
- New stages must be safe to re-run: prefer an explicit already-done check
  when the stage owns persistent state, otherwise use an operation whose
  repeat behavior is intentionally safe (see
  [Idempotence and Privilege](ARCHITECTURE.md#idempotence-and-privilege)).
- Write sudoers content only through `sudoers_write`, which validates it
  with `visudo` first.
- Regenerate `git-install.inf` with the Git for Windows installer's
  `/SAVEINF` flag (see its header) rather than hand-editing installer keys.
