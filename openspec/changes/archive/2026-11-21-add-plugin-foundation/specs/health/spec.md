# Spec Delta

## Purpose

Lets the user diagnose why the plugin is inactive or misbehaving through the standard
`:checkhealth` mechanism.

## ADDED Requirements

### Requirement: Health report
`:checkhealth chezmoi` SHALL report: the Neovim version against the minimum, whether a chezmoi
executable is found and its version against the minimum, the source directory or chezmoi's error
for it, and the number of indexed managed files.

#### Scenario: Healthy setup
- **WHEN** Neovim and chezmoi meet the minimum versions and the index is built
- **THEN** every check is reported OK and the managed-file count is shown

#### Scenario: chezmoi missing
- **WHEN** no chezmoi executable is found
- **THEN** the report shows an error for chezmoi and the remaining chezmoi checks are skipped
