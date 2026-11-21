# Proposal

## Why

Editing a `.tmpl` source gives no way to see what it renders to before saving: with
apply-on-save the rendered result lands straight in the target, and redirect keeps the target
out of view. A preview of the current buffer, including unsaved edits, lets the user check a
template before it reaches the target.

## What Changes

- New subcommand `:Chezmoi preview`: renders the current source buffer (including unsaved
  edits) through chezmoi and shows the result in a read-only vertical split.
- Only managed templates (source name ending in `.tmpl`) are previewed. Any other buffer gets an
  info message explaining why a preview does not apply; a template that fails to render is an
  error.
- The preview is on demand, not live: it re-renders when its source is written and when the
  command is run again; between those, a winbar marks it stale as soon as the source buffer
  changes.

## Capabilities

### New Capabilities
- `template-preview`: rendering a managed template buffer into a preview split, its refresh on
  write and its stale marker.

### Modified Capabilities
- `chezmoi-command`: the subcommand list (and its completion) gains `preview`.

## Impact

- New module `lua/chezmoi/preview.lua`; `lua/chezmoi/command.lua` registers the subcommand;
  `lua/chezmoi/runner.lua` gains an optional stdin argument.
- `doc/chezmoi.txt` and `README.md` document the command and its limits.
- New tests in `tests/`. No new dependencies; chezmoi >= 2.70 already provides
  `execute-template`.
