local M = {}

local did_setup = false

---Configure the plugin, activate redirect and apply-on-save, and build the index.
---Returns without waiting for chezmoi.
---@param opts? chezmoi.Options
function M.setup(opts)
  require('chezmoi.config').setup(opts)
  did_setup = true
  require('chezmoi.redirect').setup()
  require('chezmoi.apply').setup()
  require('chezmoi.index').build()
end

---Run `setup()` with defaults unless it already ran.
function M.ensure_setup()
  if not did_setup then
    M.setup()
  end
end

---@return boolean
function M.did_setup()
  return did_setup
end

---Whether the buffer's file is a managed target or the source of one. Runs no process; false
---until the index is ready.
---@param buf? integer buffer handle, 0 or nil for the current buffer
---@return boolean
function M.is_managed(buf)
  local name = vim.api.nvim_buf_get_name(buf or 0)
  return require('chezmoi.index').is_managed(name)
end

---Source path of a managed target, or nil.
---@param path string
---@return string?
function M.source_of(path)
  return require('chezmoi.index').source_of(path)
end

---Target path of a managed source, or nil.
---@param path string
---@return string?
function M.target_of(path)
  return require('chezmoi.index').target_of(path)
end

return M
