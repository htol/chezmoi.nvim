local H = require('tests.helpers')
local eq = MiniTest.expect.equality

local T, child, ctx = H.new_set()

local function buf_exists(name)
  return child.lua_get('vim.fn.bufnr(...) ~= -1', { name })
end

local function edit(path)
  child.lua('vim.cmd.edit(vim.fn.fnameescape(...))', { path })
end

T['open managed target'] = function()
  H.start(child, ctx.home)
  H.setup(child)
  edit(ctx.home .. '/.bashrc')
  H.wait(child, ('vim.api.nvim_buf_get_name(0) == %q'):format(ctx.src .. '/dot_bashrc'))
  eq(child.lua_get('vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'export A=1' })
  eq(buf_exists(ctx.home .. '/.bashrc'), false)
end

T['source already open'] = function()
  H.start(child, ctx.home)
  H.setup(child)
  edit(ctx.src .. '/dot_bashrc')
  child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })')
  local src_buf = child.lua_get('vim.api.nvim_get_current_buf()')
  child.cmd('enew')
  edit(ctx.home .. '/.bashrc')
  H.wait(child, ('vim.api.nvim_get_current_buf() == %d'):format(src_buf))
  eq(child.lua_get('vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'unsaved' })
  eq(buf_exists(ctx.home .. '/.bashrc'), false)
end

T['unmanaged file'] = function()
  H.write(ctx.home .. '/notes.txt', 'hello\n')
  H.start(child, ctx.home)
  H.setup(child)
  edit(ctx.home .. '/notes.txt')
  vim.uv.sleep(100)
  eq(H.bufname(child), ctx.home .. '/notes.txt')
  eq(child.lua_get('vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'hello' })
end

T['redirect disabled'] = function()
  H.write(ctx.home .. '/.bashrc', 'target\n')
  H.start(child, ctx.home)
  H.setup(child, { redirect = false })
  edit(ctx.home .. '/.bashrc')
  vim.uv.sleep(100)
  eq(H.bufname(child), ctx.home .. '/.bashrc')
  eq(child.lua_get('vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'target' })
end

T['template source gets the target filetype'] = function()
  H.start(child, ctx.home)
  H.setup(child)
  edit(ctx.home .. '/.gitconfig')
  H.wait(child, ('vim.api.nvim_buf_get_name(0) == %q'):format(ctx.src .. '/dot_gitconfig.tmpl'))
  eq(child.lua_get('vim.bo.filetype'), 'gitconfig')
end

T['nvim started with a managed target'] = function()
  H.write(ctx.home .. '/.bashrc', 'export A=1\n')
  H.start(child, ctx.home, { '-c', 'lua require("chezmoi").setup()', ctx.home .. '/.bashrc' })
  H.wait(child, ('vim.api.nvim_buf_get_name(0) == %q'):format(ctx.src .. '/dot_bashrc'))
  eq(buf_exists(ctx.home .. '/.bashrc'), false)
end

T['target edited before the index was ready'] = function()
  H.write(ctx.home .. '/.bashrc', 'export A=1\n')
  H.start(child, ctx.home, { ctx.home .. '/.bashrc' })
  child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "edited" })')
  H.setup(child)
  local note = H.wait_note(child, 'is a chezmoi target')
  eq(note.level, vim.log.levels.WARN)
  eq(H.bufname(child), ctx.home .. '/.bashrc')
  eq(child.lua_get('vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'edited' })
end

return T
