# Spec Delta

## MODIFIED Requirements

### Requirement: Single command with subcommands
The plugin SHALL define one user command `:Chezmoi` whose first argument selects a subcommand.
Command-line completion SHALL offer subcommand names, including aliases. An unknown or missing
subcommand SHALL produce an error listing the valid subcommands.

#### Scenario: Completion
- **WHEN** the user types `:Chezmoi ` and presses Tab
- **THEN** the completion list contains `add`, `apply`, `forget`, `manage`, `preview`, `refresh`,
  `unmanage`

#### Scenario: Unknown subcommand
- **WHEN** the user runs `:Chezmoi frobnicate`
- **THEN** an error lists the valid subcommands
