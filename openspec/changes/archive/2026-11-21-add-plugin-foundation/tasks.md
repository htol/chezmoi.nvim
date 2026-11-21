# Tasks

## 1. Scaffolding

- [x] 1.1 Add `.gitignore` (`deps/`), `.stylua.toml`, `.luarc.json` (Neovim runtime, LuaJIT) and verify `git status` shows no `deps/` after a test run
- [x] 1.2 Add `Makefile` with `deps`, `test`, `lint` targets; `make deps` clones mini.nvim into `deps/` and verify `make test` runs an empty suite with exit 0
- [x] 1.3 Add `tests/minimal_init.lua` and a test helper that starts a child Neovim with a fresh temp `HOME`/XDG dirs and a seeded chezmoi source dir (plain file, template, `run_` script, encrypted-free); verify a smoke test can run `chezmoi managed` inside it and sees only the seeded files

## 2. Core

- [x] 2.1 `config.lua`: defaults `{ cmd, redirect, apply_on_save }` with `vim.validate`; verify tests for defaults, override and rejection of a wrong type
- [x] 2.2 `runner.lua`: async `vim.system` wrapper (`stdin = false`, `--no-tty` where needed, callback scheduled on main loop); verify a test that a failing command reports exit code and trimmed stderr, and that setup returns before the process exits
- [x] 2.3 `index.lua`: parallel `source-path` + `managed --include=files --exclude=encrypted --path-style=all --format=json`, two-way maps, ready state, coalesced rebuilds, change listeners; verify managed-index scenarios (plain, template, encrypted excluded, chezmoi missing, no source dir) pass
- [x] 2.4 `init.lua`: `setup()`, `is_managed(buf)`, `source_of`, `target_of`; verify managed-buffer query scenarios pass and that `is_managed` returns false before the index is ready

## 3. Redirect

- [x] 3.1 `redirect.lua`: per-build `BufReadCmd` for indexed targets, reuse of a loaded source buffer, target buffer wiped, filetype from target path; verify source-redirect scenarios "Open managed target", "Source already open", "Unmanaged file", "Redirect disabled", "Template source"
- [x] 3.2 Post-ready sweep for buffers loaded before the index; verify scenarios "nvim started with a managed target" (child started with the target as argument) and "Target edited before the index was ready"

## 4. Apply on save

- [x] 4.1 `apply.lua`: `BufWritePost` on source dir, lookup in source→target, per-target queue (1 running + 1 pending); verify scenarios "Successful apply", "Template error", "Apply disabled", "Rapid saves"
- [x] 4.2 Non-file sources: no apply, index rebuild instead; verify "Writing a run script" (script leaves no marker file) and "Writing .chezmoiignore"
- [x] 4.3 Conflict reporting; verify "Conflicting target" keeps the direct edit and the notification names the target

## 5. :Chezmoi command

- [x] 5.1 `plugin/chezmoi.lua` + `command.lua`: dispatch table, aliases, completion, error for unknown/missing subcommand, lazy `setup()` on first use; verify "Completion" and "Unknown subcommand"
- [x] 5.2 `add`/`manage` with passthrough args; verify "Add an unmanaged file", "Add as template", "Unsaved buffer", and refusal for an already managed file
- [x] 5.3 `forget`/`unmanage` with confirmation; verify "Forget from the source buffer" and "User declines"
- [x] 5.4 `apply` and `refresh`; verify "Manual apply" (with `apply_on_save = false`) and "New file added from the shell"

## 6. Health and docs

- [x] 6.1 `health.lua`; verify "Healthy setup" and "chezmoi missing" by checking the `:checkhealth chezmoi` buffer text in a child
- [x] 6.2 `doc/chezmoi.txt` (setup, options, commands, API) and `README.md` (install with lazy.nvim, `lazy = false`, local-dev override via `dir`); verify `:helptags doc` produces no errors and `:help chezmoi` opens

## 7. Final check

- [x] 7.1 `make lint` and `make test` pass; `openspec validate add-plugin-foundation --strict` passes
- [x] 7.2 Manual smoke test in a real Neovim against a throwaway `HOME`: open a managed target, edit, save, see the target updated and the notification
