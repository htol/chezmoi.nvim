# Proposal

## Why

Editing chezmoi-managed dotfiles from Neovim is error-prone: opening `~/.bashrc` edits the
target, which the next `chezmoi apply` silently overwrites, and applying a saved source means a
trip to the shell. chezmoi.nvim needs a foundation that makes the source the only place you edit
and keeps targets in sync, without ever blocking the editor; later features (status panel, live
template preview) build on it.

## What Changes

- Opening a managed target file opens its chezmoi source instead.
- Saving a source file that maps to a managed file applies that one target, asynchronously, and
  reports the result.
- A single `:Chezmoi <subcommand>` command with completion: `add` (alias `manage`), `forget`
  (alias `unmanage`), `apply`, `refresh`.
- A Lua API answering whether a buffer is managed, for statuslines.
- `:checkhealth chezmoi`.
- Every chezmoi invocation runs asynchronously; no keymaps are defined by default.
- Repository scaffolding: plugin layout, help file, Makefile with `test` and `lint`, a headless
  test suite against an isolated chezmoi setup.

## Capabilities

### New Capabilities
- `managed-index`: discovering the chezmoi source dir and the set of managed files, keeping it
  current, and exposing whether a buffer is managed.
- `source-redirect`: opening a managed target opens its source instead.
- `apply-on-save`: applying the matching target when a source file is written.
- `chezmoi-command`: the `:Chezmoi` command, its subcommands, aliases and completion.
- `health`: `:checkhealth chezmoi` diagnostics.

### Modified Capabilities

None (greenfield).

## Impact

- New repository content only: `lua/chezmoi/`, `plugin/chezmoi.lua`, `doc/chezmoi.txt`,
  `tests/`, `Makefile`, `README.md`.
- Requires Neovim >= 0.12 and chezmoi >= 2.70 on `PATH`; no Lua plugin dependencies at runtime.
  Tests fetch mini.nvim into an ignored directory.
