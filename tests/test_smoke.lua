local H = require('tests.helpers')
local eq = MiniTest.expect.equality

local T, child, ctx = H.new_set()

T['child sees only the seeded source dir'] = function()
  H.start(child, ctx.home)
  eq(child.lua_get('vim.env.HOME'), ctx.home)
  local out = child.lua_get([[
    vim.system({ 'chezmoi', 'managed', '--include=files,scripts' }, { text = true }):wait().stdout
  ]])
  local got = vim.split(vim.trim(out), '\n')
  table.sort(got)
  eq(got, { '.bashrc', '.gitconfig', 'install.sh' })
end

return T
