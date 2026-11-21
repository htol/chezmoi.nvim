-- Minimal init for the test runner and for child Neovim instances.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(root .. '/deps/mini.nvim')
package.path = root .. '/?.lua;' .. package.path
vim.opt.swapfile = false
vim.opt.shadafile = 'NONE'

if #vim.api.nvim_list_uis() == 0 and vim.env.CHEZMOI_NVIM_CHILD == nil then
  require('mini.test').setup()
end
