local M = {}

local MIN_NVIM = '0.12.0'
local MIN_CHEZMOI = '2.70.0'

function M.check()
  local health = vim.health
  local config = require('chezmoi.config')
  local index = require('chezmoi.index')

  health.start('chezmoi.nvim')

  local nvim = vim.version()
  if vim.version.ge(nvim, MIN_NVIM) then
    health.ok(('Neovim %s (>= %s)'):format(tostring(nvim), MIN_NVIM))
  else
    health.error(('Neovim %s is older than %s'):format(tostring(nvim), MIN_NVIM))
  end

  local cmd = config.options.cmd
  if vim.fn.executable(cmd) ~= 1 then
    health.error(('chezmoi executable not found: %s'):format(cmd), {
      'Install chezmoi or set the `cmd` option of setup()',
    })
    return
  end

  -- :checkhealth is synchronous by design; these calls are short and user-initiated.
  local ver = vim.system({ cmd, '--version' }, { text = true }):wait(5000)
  local ver_str = ver.code == 0 and (ver.stdout or ''):match('v(%d+%.%d+%.%d+)') or nil
  local parsed = ver_str and vim.version.parse(ver_str)
  if not parsed then
    health.error(('cannot determine the chezmoi version from `%s --version`'):format(cmd))
  elseif vim.version.ge(parsed, MIN_CHEZMOI) then
    health.ok(('chezmoi %s (>= %s)'):format(tostring(parsed), MIN_CHEZMOI))
  else
    health.error(('chezmoi %s is older than %s'):format(tostring(parsed), MIN_CHEZMOI))
  end

  local sp = vim.system({ cmd, 'source-path' }, { text = true }):wait(5000)
  if sp.code == 0 then
    health.ok('Source directory: ' .. vim.trim(sp.stdout or ''))
  else
    health.error('chezmoi source-path failed: ' .. vim.trim(sp.stderr or ''))
  end

  if index.ready then
    health.ok(('Index: %d managed files'):format(index.count))
  elseif index.error then
    health.error('Index: ' .. index.error)
  elseif not require('chezmoi').did_setup() then
    health.warn('Index not built: setup() has not been called')
  else
    health.warn('Index not built yet')
  end
end

return M
