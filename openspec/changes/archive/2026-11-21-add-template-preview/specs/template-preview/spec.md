# Spec Delta

## Purpose

Shows what a managed chezmoi template renders to, including unsaved edits, in a split next to
the source, so a template can be checked before it reaches its target.

## ADDED Requirements

### Requirement: Render the current template buffer
`:Chezmoi preview` SHALL render the current buffer's text, including unsaved changes, as a
chezmoi template and show the result in a vertical split next to the source window. The preview
buffer SHALL be read-only, SHALL not be associated with a file, and SHALL use the filetype of the
target. Running the command again for the same source SHALL re-render into the existing preview
window instead of opening another one. The source window SHALL keep focus.

#### Scenario: Preview a saved template
- **WHEN** the current buffer is `dot_gitconfig.tmpl` containing `name = {{ "test" }}` and the
  user runs `:Chezmoi preview`
- **THEN** a vertical split shows `name = test`
- **AND** the preview buffer is not modifiable and its filetype is `gitconfig`
- **AND** the cursor stays in the source window

#### Scenario: Unsaved edits are rendered
- **WHEN** the user changes `{{ "test" }}` to `{{ "other" }}` in `dot_gitconfig.tmpl` without
  saving and runs `:Chezmoi preview`
- **THEN** the preview shows `name = other`
- **AND** the source file on disk and the target are unchanged

#### Scenario: Repeated command reuses the window
- **WHEN** a preview of `dot_gitconfig.tmpl` is open and the user runs `:Chezmoi preview` again
  from the source
- **THEN** the number of windows does not change and the preview shows the new render

### Requirement: Only managed templates are previewed
The command SHALL preview only a buffer whose file is the source of a managed target and whose
source name ends in `.tmpl`. For any other buffer it SHALL open no window and SHALL show an
info-level message saying why a preview does not apply:
- a managed source that is not a template: its target is the source content as is;
- a managed target (when redirect is disabled): the template is in its source, which the
  message names;
- a buffer with no file, or a file chezmoi does not manage: it is not managed by chezmoi.

#### Scenario: Managed source that is not a template
- **WHEN** the current buffer is `dot_bashrc` and the user runs `:Chezmoi preview`
- **THEN** no window opens
- **AND** an info message says `~/.bashrc` is not a template

#### Scenario: Unmanaged file
- **WHEN** the current buffer is an unmanaged `~/notes.txt` and the user runs `:Chezmoi preview`
- **THEN** no window opens
- **AND** an info message says the file is not managed by chezmoi

#### Scenario: Target buffer with redirect disabled
- **WHEN** `redirect` is `false`, the current buffer is `~/.gitconfig` and the user runs
  `:Chezmoi preview`
- **THEN** no window opens
- **AND** an info message names `dot_gitconfig.tmpl` as the file to preview from

### Requirement: Render failures are errors
When chezmoi fails to render the buffer, the command SHALL show an error notification with
chezmoi's error output. When no preview is open for that source, no window SHALL open. When a
preview is open, it SHALL keep its previous content and SHALL be marked stale.

#### Scenario: Broken template, no preview open
- **WHEN** the current buffer is `dot_gitconfig.tmpl` containing `{{ if` and the user runs
  `:Chezmoi preview`
- **THEN** an error notification contains chezmoi's error
- **AND** no window opens

#### Scenario: Broken template, preview open
- **WHEN** a preview shows `name = test` and the user breaks the template and runs
  `:Chezmoi preview`
- **THEN** an error notification contains chezmoi's error
- **AND** the preview still shows `name = test` and is marked stale

### Requirement: Re-render on write
While a preview is open, writing its source SHALL re-render the preview, regardless of the
`apply_on_save` option. After the preview window is closed, writing the source SHALL neither
render nor reopen it.

#### Scenario: Write refreshes the preview
- **WHEN** a preview of `dot_gitconfig.tmpl` is open and the user changes the template and runs
  `:write`
- **THEN** the preview shows the new render and is not marked stale

#### Scenario: Closed preview stays closed
- **WHEN** the user closed the preview window and then writes `dot_gitconfig.tmpl`
- **THEN** no preview window opens

### Requirement: Stale marker
The preview window SHALL show in its winbar the target path and whether the preview matches the
source buffer. As soon as the source buffer's text changes after the last successful render, the
winbar SHALL mark the preview stale, without running chezmoi. A successful render SHALL clear the
mark. The stale mark SHALL use its own highlight group, linked to `WarningMsg` by default.

#### Scenario: Edit marks the preview stale
- **WHEN** a preview is open and up to date and the user edits the source buffer
- **THEN** the preview winbar marks it stale
- **AND** no chezmoi process is started by the edit

#### Scenario: Render clears the mark
- **WHEN** the preview is marked stale and the user runs `:Chezmoi preview`
- **THEN** the winbar no longer marks it stale
