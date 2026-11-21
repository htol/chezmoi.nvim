# Tasks

## 1. Runner

- [x] 1.1 Add an optional `opts.stdin` argument to `runner.run` in `lua/chezmoi/runner.lua`,
  passed to `vim.system`; verify with a new case in the `runner` set of `tests/test_core.lua`
  that feeds stdin to a shell command and checks its stdout, and that the existing runner cases
  still pass

## 2. Preview module

- [x] 2.1 Create `lua/chezmoi/preview.lua` with `open(source_buf, target)`: read the buffer text
  (final `\n` per `'eol'`), render via `execute-template` on stdin, and on the first success open
  a read-only `nofile` buffer named `chezmoi://preview/<target>` with the target's filetype in a
  vertical split without taking focus; on a later call reuse the window; verify with tests in a
  new `tests/test_preview.lua`: saved template renders `name = test`, filetype `gitconfig`,
  focus stays in the source, a repeated call keeps the window count
- [x] 2.2 Render unsaved edits; verify with a test that edits `dot_gitconfig.tmpl` without saving
  and expects `name = other`, with the source file and target unchanged on disk
- [x] 2.3 Generation counter and `changedtick` capture so only the latest render is applied;
  verify with a test that starts two renders back to back and expects the second result
- [x] 2.4 Render failure: error notification with chezmoi's stderr, no window when none is open,
  previous content kept otherwise; verify with tests for `{{ if` with and without an open preview
- [x] 2.5 Winbar with target path and stale marker, `ChezmoiPreviewStale` highlight linked to
  `WarningMsg` with `default = true`, updated from buffer-local `TextChanged`/`TextChangedI`;
  verify with tests that an edit marks stale without starting a process (runner call count
  unchanged), and that a render clears the mark
- [x] 2.6 Buffer-local `BufWritePost` re-render, `BufWipeout` cleanup on both buffers in the
  `chezmoi.preview` augroup; verify with tests that `:write` refreshes the preview with
  `apply_on_save = false`, and that after closing the preview window a write opens nothing and
  leaves no autocmds in the group

## 3. Subcommand

- [x] 3.1 Register `preview` in `M.subcommands` in `lua/chezmoi/command.lua`: wait for the index
  with `with_index`, classify the buffer and call `preview.open` only for a `.tmpl` source;
  info messages for a non-template source, a target (naming its source) and an unmanaged or
  file-less buffer; verify with tests for `dot_bashrc`, `~/notes.txt` and `~/.gitconfig` with
  `redirect = false`, each expecting an INFO note and no new window
- [x] 3.2 Update the completion test in `tests/test_command.lua` and the unknown-subcommand
  message test to include `preview`, and the command `desc` in `plugin/chezmoi.lua`; verify
  `make test` passes

## 4. Docs and checks

- [x] 4.1 Document `:Chezmoi preview` in `doc/chezmoi.txt` (tag `*:Chezmoi-preview*`, stale
  marker, re-render on write, `ChezmoiPreviewStale`, `.chezmoi.sourceFile` is `"stdin"`) and in
  the subcommand line of `README.md`; verify `:helptags doc` reports no errors
- [x] 4.2 Run `make test` and `make lint`; both pass
