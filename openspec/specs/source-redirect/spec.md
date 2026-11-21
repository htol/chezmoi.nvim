# source-redirect Specification

## Purpose

Makes the chezmoi source the only place a managed dotfile is edited, by opening the source
whenever the user opens the target.

## Requirements

### Requirement: Opening a target opens its source
When the user opens a file that is a target in the index, the plugin SHALL show the source file
in that window instead, and SHALL NOT leave a buffer for the target behind. Redirect SHALL be
disabled when the `redirect` option is false.

#### Scenario: Open managed target
- **WHEN** the user runs `:edit ~/.bashrc` and `~/.bashrc` is managed from `dot_bashrc`
- **THEN** the window shows `dot_bashrc`
- **AND** no buffer named `~/.bashrc` exists

#### Scenario: Source already open
- **WHEN** `dot_bashrc` is already loaded and the user opens `~/.bashrc`
- **THEN** the window shows the existing `dot_bashrc` buffer, including its unsaved changes

#### Scenario: Unmanaged file
- **WHEN** the user opens a file that is not in the index
- **THEN** the file opens normally

#### Scenario: Redirect disabled
- **WHEN** setup ran with `redirect = false` and the user opens a managed target
- **THEN** the target opens normally

### Requirement: Filetype follows the target
A redirected source buffer SHALL get the filetype that its target path would get, so that
`dot_bashrc` and `dot_gitconfig.tmpl` are highlighted as their targets.

#### Scenario: Template source
- **WHEN** `~/.gitconfig` is redirected to `dot_gitconfig.tmpl`
- **THEN** the source buffer has filetype `gitconfig`

### Requirement: Targets opened before the index is ready
Buffers for managed targets that were loaded before the index became ready SHALL be redirected
once it is ready, unless they have unsaved changes.

#### Scenario: nvim started with a managed target
- **WHEN** the user runs `nvim ~/.bashrc`
- **THEN** the window shows `dot_bashrc` once the index is ready

#### Scenario: Target edited before the index was ready
- **WHEN** a managed target buffer has unsaved changes when the index becomes ready
- **THEN** that buffer is not redirected and the user is warned that it is a chezmoi target
