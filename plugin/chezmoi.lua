if vim.g.loaded_chezmoi then
  return
end
vim.g.loaded_chezmoi = true

vim.api.nvim_create_user_command('Chezmoi', function(opts)
  require('chezmoi.command').dispatch(opts)
end, {
  nargs = '*',
  complete = function(arglead, cmdline, pos)
    return require('chezmoi.command').complete(arglead, cmdline, pos)
  end,
  desc = 'chezmoi: add, forget, apply, preview, refresh',
})
