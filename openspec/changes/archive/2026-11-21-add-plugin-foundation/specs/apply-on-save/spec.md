# Spec Delta

## Purpose

Keeps a target in sync with its source by applying exactly that target whenever its source file
is written, so an edit takes effect without leaving the editor.

## ADDED Requirements

### Requirement: Writing a source applies its target
When a buffer whose file is the source of an indexed target is written, the plugin SHALL apply
that single target asynchronously and report success or failure through `vim.notify`. It SHALL
be disabled when the `apply_on_save` option is false. The plugin SHALL never apply anything
other than the targets it was asked about.

#### Scenario: Successful apply
- **WHEN** the user writes `dot_bashrc`
- **THEN** `~/.bashrc` is updated from it
- **AND** an info notification names `~/.bashrc`

#### Scenario: Template error
- **WHEN** the user writes `dot_gitconfig.tmpl` containing a template syntax error
- **THEN** `~/.gitconfig` is unchanged
- **AND** an error notification contains chezmoi's error message

#### Scenario: Apply disabled
- **WHEN** setup ran with `apply_on_save = false` and the user writes `dot_bashrc`
- **THEN** `~/.bashrc` is unchanged and no notification is shown

### Requirement: Files that are not file sources are never applied
Writing a file in the source directory that is not the source of an indexed target (a script,
`.chezmoiignore`, data files, templates under `.chezmoitemplates`) SHALL NOT run `chezmoi apply`.

#### Scenario: Writing a run script
- **WHEN** the user writes `run_onchange_install.sh` in the source directory
- **THEN** the script is not executed

### Requirement: Target modified outside chezmoi
If the target was changed since chezmoi last wrote it, the plugin SHALL NOT overwrite it, and
SHALL report an error naming the target.

#### Scenario: Conflicting target
- **WHEN** `~/.bashrc` was edited directly and the user writes `dot_bashrc`
- **THEN** `~/.bashrc` keeps the direct edit
- **AND** an error notification names `~/.bashrc`

### Requirement: Writes are applied in order
Successive writes of the same source SHALL be applied in order, and the target SHALL end up
matching the last written source.

#### Scenario: Rapid saves
- **WHEN** the user writes `dot_bashrc` twice before the first apply finishes
- **THEN** `~/.bashrc` matches the second write
