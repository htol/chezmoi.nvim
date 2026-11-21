local M = {}

---@class chezmoi.Options
---@field cmd string chezmoi executable
---@field redirect boolean open the source when a managed target is opened
---@field apply_on_save boolean apply the target when its source is written

---@type chezmoi.Options
M.defaults = {
  cmd = 'chezmoi',
  redirect = true,
  apply_on_save = true,
}

---@type chezmoi.Options
M.options = vim.deepcopy(M.defaults)

---@param opts? table
---@return chezmoi.Options
function M.setup(opts)
  vim.validate('opts', opts, 'table', true)
  local options = vim.tbl_extend('force', vim.deepcopy(M.defaults), opts or {})
  vim.validate('cmd', options.cmd, 'string')
  vim.validate('redirect', options.redirect, 'boolean')
  vim.validate('apply_on_save', options.apply_on_save, 'boolean')
  M.options = options
  return options
end

return M
