# Design

## Context

All chezmoi calls go through `runner.run(args, cb)` (`lua/chezmoi/runner.lua`), which wraps
`vim.system` and has no way to pass stdin. The index (`lua/chezmoi/index.lua`) already maps a
source path to its target without running a process, and `command.lua` has the pattern for
waiting on the index (`with_index`) and for registering subcommands (`M.subcommands`).
`redirect.show_source` sets a source buffer's filetype from its target with
`vim.filetype.match`. The test fixture already seeds `dot_gitconfig.tmpl`.

`chezmoi execute-template` with no template arguments reads the template from stdin. Checked
against chezmoi 2.74: template directives such as `chezmoi:template:left-delimiter` in the
stdin text are honoured, and `.chezmoi.sourceFile` is `"stdin"`.

## Goals / Non-Goals

**Goals:**
- One async render per command or write; no process on text changes.
- Correct result when renders overlap (a write during a manual render, two quick writes).
- Preview state disappears with its window; nothing keeps running for a closed preview.

**Non-Goals:**
- Live re-rendering on text change, and a diff against the target.
- Special handling of `modify_*.tmpl` (the rendered script is shown as is) and of
  `.chezmoi.toml.tmpl` / `--init` templates (not in the index, so "not managed").

## Decisions

**Render the buffer through stdin, not the file.** `runner.run` gains an optional third argument
`opts` with `stdin` (a string), passed through to `vim.system`. The text is the buffer's lines
joined with `\n`, plus a final `\n` when `'eol'` is set, so a saved buffer renders exactly like
the file. Alternative: `execute-template --file <source>` renders only what is on disk, which
defeats the purpose.

**One preview per source buffer, state in a table keyed by the source buffer.** State holds the
preview buffer, a render generation counter and the source `changedtick` of the last successful
render. The preview buffer is `buftype=nofile`, `bufhidden=wipe`, `swapfile=false`,
`modifiable=false` (toggled only while writing lines), named `chezmoi://preview/<target>` so it
is recognisable in buffer lists. Alternative: a single global preview — breaks as soon as two
templates are open side by side.

**Window: `nvim_open_win(buf, false, { vertical = true, win = source_win })`.** `enter = false`
keeps focus in the source without a window round-trip, and `vertical` respects `'splitright'`.
If the preview buffer is already shown in some window, no new window is opened. The window is
opened only after the first successful render, so a broken template never leaves an empty split.

**Overlapping renders: last request wins.** Each render increments the generation; a result
whose generation is not the latest is dropped. The `changedtick` is captured when the text is
read, not when the result arrives, so edits made during a render leave the preview stale.

**Staleness from `changedtick`, shown in the winbar.** Buffer-local `TextChanged`/`TextChangedI`
autocmds on the source compare its `changedtick` with the stored one and update the winbar of
every window showing the preview. A render failure leaves the stored tick unchanged, so the
preview shows stale after a failed write-render with no extra code path. Highlight group
`ChezmoiPreviewStale`, defined with `default = true` and linked to `WarningMsg`, so colour
schemes can override it. Undo back to the rendered text still shows stale; comparing text on
every change is not worth it.

**Lifecycle through autocmds in an `chezmoi.preview` augroup.** Buffer-local on the source:
`TextChanged`/`TextChangedI` (stale marker), `BufWritePost` (re-render), `BufWipeout` (close the
preview). On the preview buffer: `BufWipeout` deletes the source's autocmds and state, so
closing the window (which wipes the buffer) stops all refreshing. The write-render lives here,
not in `apply.lua`, so it is independent of `apply_on_save`.

**Eligibility check in `command.lua`, rendering in a new `lua/chezmoi/preview.lua`.** The
subcommand waits for the index with the existing `with_index`, classifies the buffer (template
source / non-template source / target / unmanaged) and calls `preview.open(buf, target)` only
for a template source. Messages for the other cases are info level, per the spec.

## Risks / Trade-offs

- [Templates that call password managers] → a render calls them, but only on command or write,
  the same occasions on which apply-on-save already renders the template.
- [`.chezmoi.sourceFile` is `"stdin"` in the preview] → templates that depend on it render
  differently than on apply; documented in `doc/chezmoi.txt`.
- [Large output] → the result is written to a scratch buffer once per render; no streaming
  needed for dotfiles.
