# managed-index Specification

## Purpose

Knows where the chezmoi source directory is and which target files chezmoi manages, so every
other feature can map a target to its source and decide whether a buffer is managed.

## Requirements

### Requirement: Index is built asynchronously at setup
The plugin SHALL build the index of managed files and the source directory without blocking the
editor. Until the index is ready, the plugin SHALL treat every buffer as not managed.

#### Scenario: Startup does not wait for chezmoi
- **WHEN** setup runs
- **THEN** setup returns before any chezmoi process exits
- **AND** the index becomes ready once chezmoi has answered

#### Scenario: chezmoi is not installed
- **WHEN** setup runs and no chezmoi executable is found
- **THEN** the plugin stays inactive and shows a single warning

#### Scenario: chezmoi has no source directory
- **WHEN** chezmoi reports an error for the source directory
- **THEN** the plugin stays inactive and shows a single warning containing chezmoi's message

### Requirement: Index maps targets to sources
The index SHALL contain only managed regular files (not directories, symlinks, scripts or
encrypted files), each with its absolute target path and absolute source path.

#### Scenario: Plain file
- **WHEN** chezmoi manages `~/.bashrc` from `dot_bashrc`
- **THEN** the index maps the absolute path of `~/.bashrc` to the absolute path of `dot_bashrc`

#### Scenario: Template
- **WHEN** chezmoi manages `~/.gitconfig` from `dot_gitconfig.tmpl`
- **THEN** the index maps `~/.gitconfig` to `dot_gitconfig.tmpl`

#### Scenario: Encrypted file is excluded
- **WHEN** chezmoi manages a target from an `encrypted_` source
- **THEN** that target is not in the index

### Requirement: Index refresh
The index SHALL be rebuilt when the user runs `:Chezmoi refresh`, after a successful
`:Chezmoi add` or `:Chezmoi forget`, and after a file inside the source directory that is not
itself a managed source is written (for example `.chezmoiignore` or `.chezmoidata.toml`).

#### Scenario: Writing .chezmoiignore
- **WHEN** the user writes `.chezmoiignore` in the source directory
- **THEN** the index is rebuilt and reflects the new ignore rules

### Requirement: Managed-buffer query
The plugin SHALL expose a Lua function that reports whether a buffer is managed. A buffer is
managed when its file is a target in the index or a source file of an indexed target. The
function SHALL return without running any process.

#### Scenario: Source buffer
- **WHEN** the current buffer is `dot_bashrc` in the source directory
- **THEN** the query returns true

#### Scenario: Unmanaged buffer
- **WHEN** the current buffer is a file chezmoi does not manage
- **THEN** the query returns false
