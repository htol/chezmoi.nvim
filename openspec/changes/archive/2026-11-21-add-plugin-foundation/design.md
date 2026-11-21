# Design

## Context

Greenfield repository. A single-file prototype in the user's dotfiles shows the intended
behaviour but blocks on `vim.fn.system`, calls `chezmoi source-path` once per file, and runs
`chezmoi apply --source-path` for any file written under the source dir — which executes `run_`
scripts (verified: `chezmoi apply --source-path run_x.sh` runs the script). Requirements are in
the specs of this change; see proposal.md for motivation.

Facts the design relies on (verified against chezmoi 2.70.2):
- `chezmoi managed --include=files --exclude=encrypted --path-style=all --format=json` returns,
  in one call, a map whose values hold `absolute` (target) and `sourceAbsolute` (source).
- `chezmoi source-path` with no argument prints the source dir (honours `.chezmoiroot`).
- `chezmoi apply --no-tty` on a target changed outside chezmoi, with stdin at EOF, exits 1 with
  "has changed since chezmoi last wrote it" and leaves the target untouched.

## Goals / Non-Goals

**Goals:**
- No synchronous process execution anywhere on the editor's main path.
- One module per concern so the status panel and live preview can reuse the runner and index.
- Behaviour testable headless against a throwaway `HOME`.

**Non-Goals:**
- Status panel, diff view, template preview, picker integration (follow-up changes).
- Encrypted sources, symlinks, external (`.chezmoiexternal`) entries.
- Default keymaps.

## Decisions

### Module layout
```
plugin/chezmoi.lua        defines :Chezmoi only (cheap; nothing runs until setup or first use)
lua/chezmoi/init.lua      setup(opts), public API: is_managed(buf), source_of(path), target_of(path)
lua/chezmoi/config.lua    defaults + validation (vim.validate)
lua/chezmoi/runner.lua    vim.system wrapper: argv build, --no-tty, stdin closed, callback on main loop
lua/chezmoi/index.lua     source dir + target<->source maps, async build, change listeners
lua/chezmoi/redirect.lua  BufReadCmd autocmd + post-ready sweep of loaded buffers
lua/chezmoi/apply.lua     BufWritePost handler, per-target serial queue
lua/chezmoi/command.lua   subcommand table, dispatch, completion
lua/chezmoi/health.lua    :checkhealth chezmoi
```
Options: `{ cmd = "chezmoi", redirect = true, apply_on_save = true }`. `setup()` is required to
activate autocmds; `:Chezmoi` lazily calls `setup()` with defaults if it has not run, so the
command works without explicit configuration.

### Index from one JSON call, built with two parallel processes
`source-path` and `managed --format=json` run concurrently; the index flips to ready when both
succeed. Two Lua tables (target→source, source→target) give O(1), process-free lookups for
`is_managed`, redirect and apply. Paths are normalised with `vim.fs.normalize` +
`vim.uv.fs_realpath` on the source dir so symlinked homes compare equal.
Alternative: per-file `chezmoi source-path` (prototype) — one process per open, and blocking.

A rebuild while one is in flight sets a "dirty" flag and re-runs once on completion, instead of
racing two builds.

### Redirect via BufReadCmd with an explicit pattern list
After each index build, the redirect augroup is recreated with one `BufReadCmd` autocmd whose
`pattern` is the list of indexed targets. Neovim never reads the target; the handler loads the
source into the window (reusing an already loaded source buffer) and wipes the target buffer,
then sets the filetype from `vim.filetype.match({ filename = target })`.
Alternatives: `BufReadPre` cannot cancel the read; a `*` `BufReadCmd` would make the plugin
responsible for reading every file. ~150 patterns is cheap for autocmd matching.

Buffers loaded before the first index build (e.g. `nvim ~/.bashrc`) are handled by a one-time
sweep when the index becomes ready: unmodified managed-target buffers are redirected in every
window showing them; modified ones get a warning.

### Apply only indexed sources, serially per target
`BufWritePost` on `<source_dir>/*` looks the file up in source→target. Hit: enqueue an apply for
that target. Miss: no apply; if the file is inside the source dir, schedule an index rebuild
(covers `.chezmoiignore`, `.chezmoidata.*`, `.chezmoitemplates/*`). This is what keeps `run_`
scripts from executing.

The apply command is `chezmoi apply --no-tty <target>` (by target path, not `--source-path`, so
the same function serves `:Chezmoi apply` from either buffer). Each target has a queue of length
≤ 1 pending + 1 running: a save during a running apply replaces the pending entry, so the last
write wins without piling up processes.

Errors are reported with chezmoi's stderr, trimmed; the "has changed since chezmoi last wrote it"
case is reported as a conflict that names the target and suggests `chezmoi diff`/`merge` from a
shell (a diff view arrives with the status panel).

### Runner never blocks and never prompts
All processes go through `runner.run(args, opts, cb)` → `vim.system({cmd, unpack(args)},
{ text = true, stdin = false })` with `--no-tty` added for commands that may prompt. Callbacks
are wrapped in `vim.schedule_wrap`. `forget` passes `--force` because the confirmation is asked
in Neovim (`vim.ui.select`/`vim.fn.confirm`) before the process starts.

### Command dispatch table
`command.lua` holds `{ name = { run = fn, complete = fn?, alias_of = name? } }`. Completion
lists all keys; `add` completes a few common `chezmoi add` flags (`--template`, `--encrypt` is
deliberately left out since encrypted sources are a non-goal). New subcommands from later
changes register into the same table.

### Tests
mini.test, run by `make test` as `nvim --headless --noplugin -u tests/minimal_init.lua`. The
Makefile clones mini.nvim into `deps/` (gitignored) on first run. Each test case creates a fresh
temp dir and sets `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`,
`XDG_CACHE_HOME` for a child Neovim (`MiniTest.new_child_neovim`), so chezmoi and the plugin see
only the throwaway source dir. Async waits use `vim.wait` with a timeout in the child.
`make lint` runs `stylua --check` and `lua-language-server --check`.

## Risks / Trade-offs

- [Index stale after shell-side `chezmoi add`] → `:Chezmoi refresh`; rebuild also triggered by
  writes in the source dir. A filesystem watcher is deferred.
- [BufReadCmd replaces normal reading for targets] → handler must also fire `BufReadPost`-
  equivalent behaviour for the source (it does a real `:edit` of the source, so standard
  autocmds run for it).
- [Plugin managers that lazy-load on command only] → redirect/apply would not be active until
  first `:Chezmoi`; README recommends `lazy = false` (setup is cheap).
- [chezmoi output format changes] → minimum chezmoi version checked in health; JSON parse
  failures surface as a single error notification.

## Migration Plan

The dotfiles repository later replaces `require('config.chezmoi')` with a lazy.nvim spec for
`htol/chezmoi.nvim`, and the lualine component switches from `_G.chezmoi.is_managed()` to
`require('chezmoi').is_managed(0)`. That is a separate edit in that repository, shown as a diff
before it is made.
