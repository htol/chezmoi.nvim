local H = require('tests.helpers')
local eq = MiniTest.expect.equality

local T, child, ctx = H.new_set()

local function checkhealth()
  child.cmd('checkhealth chezmoi')
  return table.concat(child.lua_get('vim.api.nvim_buf_get_lines(0, 0, -1, false)'), '\n')
end

local function has(text, needle)
  MiniTest.expect.no_equality(text:find(needle, 1, true), nil)
end

T['healthy setup'] = function()
  H.start(child, ctx.home)
  H.setup(child)
  local text = checkhealth()
  has(text, 'Neovim')
  has(text, 'chezmoi 2.')
  has(text, 'Source directory: ' .. ctx.src)
  has(text, 'Index: 2 managed files')
  eq(text:find('ERROR', 1, true), nil)
  eq(text:find('WARNING', 1, true), nil)
end

T['chezmoi missing'] = function()
  H.start(child, ctx.home)
  child.lua('require("chezmoi").setup({ cmd = "chezmoi-does-not-exist" })')
  local text = checkhealth()
  has(text, 'ERROR chezmoi executable not found: chezmoi-does-not-exist')
  eq(text:find('Source directory', 1, true), nil)
  eq(text:find('Index', 1, true), nil)
end

return T
