# chezmoi.nvim

Edit [chezmoi](https://www.chezmoi.io)-managed dotfiles from Neovim without editing the wrong
file:

- Opening a managed target (`~/.bashrc`) opens its source (`dot_bashrc`) instead, with the
  target's filetype.
- Writing a source applies exactly that target, asynchronously, and reports the result. Scripts
  are never run.
- `:Chezmoi add | manage | forget | unmanage | apply | refresh`.
- `require('chezmoi').is_managed(0)` for statuslines.
- `:checkhealth chezmoi`.

Requires Neovim >= 0.12 and chezmoi >= 2.70. No default keymaps.

## Why

With chezmoi, `~/.bashrc` is generated from `dot_bashrc` in the source directory. Opening
`~/.bashrc` and editing it is the natural thing to do, and the next `chezmoi apply` silently
overwrites that edit. Getting a source change into effect means a trip to the shell. This plugin
makes the source the only place you edit and keeps the target in sync on every save.

## Install

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'htol/chezmoi.nvim',
  lazy = false, -- setup is cheap; redirect and apply-on-save need it at startup
  opts = {},
}
```

To work on a local checkout, point the spec at it:

```lua
{
  'htol/chezmoi.nvim',
  dir = '/path/to/your/chezmoi.nvim/checkout',
  lazy = false,
  opts = {},
}
```

## Options

```lua
require('chezmoi').setup({
  cmd = 'chezmoi',      -- chezmoi executable
  redirect = true,      -- open the source when a managed target is opened
  apply_on_save = true, -- apply the target when its source is written
})
```

See `:help chezmoi` for commands and the Lua API.

## Development

```sh
make test   # headless mini.test suite against a throwaway HOME (clones mini.nvim into deps/)
make lint   # stylua --check and lua-language-server --check
```

To try the plugin by hand without touching your own config, run this from the repository root.
Every XDG directory points inside a throwaway `HOME`, so nothing is written elsewhere:

```sh
tmp=$(mktemp -d)
mkdir -p "$tmp/.local/share/chezmoi"
echo 'export A=1' > "$tmp/.local/share/chezmoi/dot_bashrc"
env HOME="$tmp" XDG_CONFIG_HOME="$tmp/.config" XDG_DATA_HOME="$tmp/.local/share" \
  XDG_STATE_HOME="$tmp/.local/state" XDG_CACHE_HOME="$tmp/.cache" \
  nvim --clean --cmd "set rtp^=$PWD" -c 'runtime plugin/chezmoi.lua' \
  -c 'lua require("chezmoi").setup()' "$tmp/.bashrc"
```

The window switches to `dot_bashrc`; edit it, `:w`, and `$tmp/.bashrc` is updated. Remove `$tmp`
afterwards.
