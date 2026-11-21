# Spec Delta

## Purpose

Provides one `:Chezmoi` user command whose subcommands cover the everyday chezmoi operations on
the current file, with completion, instead of a separate command per operation.

## ADDED Requirements

### Requirement: Single command with subcommands
The plugin SHALL define one user command `:Chezmoi` whose first argument selects a subcommand.
Command-line completion SHALL offer subcommand names, including aliases. An unknown or missing
subcommand SHALL produce an error listing the valid subcommands.

#### Scenario: Completion
- **WHEN** the user types `:Chezmoi ` and presses Tab
- **THEN** the completion list contains `add`, `apply`, `forget`, `manage`, `refresh`, `unmanage`

#### Scenario: Unknown subcommand
- **WHEN** the user runs `:Chezmoi frobnicate`
- **THEN** an error lists the valid subcommands

### Requirement: add / manage
`:Chezmoi add [args]` SHALL add the current buffer's file to chezmoi, passing any extra arguments
to `chezmoi add` (for example `--template`), then rebuild the index and show the new source in
the current window. `manage` SHALL be an alias. It SHALL refuse a buffer with unsaved changes, a
buffer with no file, and a file that is already managed.

#### Scenario: Add an unmanaged file
- **WHEN** the current buffer is a saved, unmanaged `~/.inputrc` and the user runs `:Chezmoi add`
- **THEN** chezmoi manages `~/.inputrc`
- **AND** the window shows its new source file

#### Scenario: Add as template
- **WHEN** the user runs `:Chezmoi manage --template` on an unmanaged file
- **THEN** the new source file name ends in `.tmpl`

#### Scenario: Unsaved buffer
- **WHEN** the current buffer has unsaved changes and the user runs `:Chezmoi add`
- **THEN** nothing is added and an error asks to save first

### Requirement: forget / unmanage
`:Chezmoi forget` SHALL, after the user confirms, stop chezmoi managing the current file (whether
the buffer is the target or the source), delete the source, keep the target file, rebuild the
index and show the target in the current window. `unmanage` SHALL be an alias. It SHALL refuse
an unmanaged buffer and a buffer with unsaved changes.

#### Scenario: Forget from the source buffer
- **WHEN** the current buffer is `dot_inputrc` and the user runs `:Chezmoi forget` and confirms
- **THEN** chezmoi no longer manages `~/.inputrc`
- **AND** `~/.inputrc` still exists with its content
- **AND** the window shows `~/.inputrc`

#### Scenario: User declines
- **WHEN** the user runs `:Chezmoi unmanage` and answers no
- **THEN** nothing changes

### Requirement: apply
`:Chezmoi apply` SHALL apply the target of the current buffer, with the same reporting and
conflict behaviour as apply-on-save, regardless of the `apply_on_save` option. It SHALL refuse a
buffer that is not managed.

#### Scenario: Manual apply
- **WHEN** the current buffer is `dot_bashrc` and the user runs `:Chezmoi apply`
- **THEN** `~/.bashrc` is updated and an info notification names it

### Requirement: refresh
`:Chezmoi refresh` SHALL rediscover the source directory, rebuild the index and notify when done.

#### Scenario: New file added from the shell
- **WHEN** the user ran `chezmoi add ~/.inputrc` in a shell and then `:Chezmoi refresh`
- **THEN** opening `~/.inputrc` opens its source
