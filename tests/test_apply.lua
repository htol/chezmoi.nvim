local H = require('tests.helpers')
local eq = MiniTest.expect.equality

local T, child, ctx = H.new_set()

---Edit `path` in the child, replace its content with `lines` and write it.
local function write_buf(path, lines)
  child.lua('vim.cmd.edit(vim.fn.fnameescape(...))', { path })
  child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, ...)', { lines })
  child.cmd('silent write')
end

T['successful apply'] = function()
  H.start(child, ctx.home)
  H.setup(child)
  write_buf(ctx.src .. '/dot_bashrc', { 'export A=2' })
  local note = H.wait_note(child, 'applied ~/.bashrc')
  eq(note.level, vim.log.levels.INFO)
  eq(H.read(ctx.home .. '/.bashrc'), 'export A=2\n')
end

T['template error'] = function()
  H.chezmoi(ctx.home, { 'apply' })
  local before = H.read(ctx.home .. '/.gitconfig')
  H.start(child, ctx.home)
  H.setup(child)
  write_buf(ctx.src .. '/dot_gitconfig.tmpl', { '[user]', '\tname = {{ .nope' })
  local note = H.wait_note(child, 'applying ~/.gitconfig failed')
  eq(note.level, vim.log.levels.ERROR)
  MiniTest.expect.no_equality(note.msg:find('template', 1, true), nil)
  eq(H.read(ctx.home .. '/.gitconfig'), before)
end

T['apply disabled'] = function()
  H.start(child, ctx.home)
  H.setup(child, { apply_on_save = false })
  write_buf(ctx.src .. '/dot_bashrc', { 'export A=2' })
  vim.uv.sleep(500)
  eq(H.read(ctx.home .. '/.bashrc'), nil)
  eq(H.notes(child), {})
end

T['rapid saves'] = function()
  H.start(child, ctx.home)
  H.setup(child)
  child.lua('vim.cmd.edit(vim.fn.fnameescape(...))', { ctx.src .. '/dot_bashrc' })
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'first' })
    vim.cmd('silent write')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'second' })
    vim.cmd('silent write')
  ]])
  H.wait(child, '#_G.notes >= 2')
  vim.uv.sleep(300)
  eq(H.read(ctx.home .. '/.bashrc'), 'second\n')
  for _, note in ipairs(H.notes(child)) do
    eq(note.level, vim.log.levels.INFO)
  end
end

T['writing a run script does not execute it'] = function()
  H.start(child, ctx.home)
  H.setup(child)
  write_buf(ctx.src .. '/run_onchange_install.sh', { '#!/bin/sh', 'touch "$HOME/script-ran"', '' })
  vim.uv.sleep(700)
  eq(vim.uv.fs_stat(ctx.home .. '/script-ran'), nil)
  eq(H.notes(child), {})
end

T['writing .chezmoiignore rebuilds the index'] = function()
  H.start(child, ctx.home)
  H.setup(child)
  eq(child.lua_get('require("chezmoi").source_of("~/.bashrc") ~= nil'), true)
  write_buf(ctx.src .. '/.chezmoiignore', { '.bashrc' })
  H.wait(child, 'require("chezmoi").source_of("~/.bashrc") == nil')
  eq(child.lua_get('require("chezmoi.index").count'), 1)
end

T['conflicting target keeps the direct edit'] = function()
  H.chezmoi(ctx.home, { 'apply' })
  H.write(ctx.home .. '/.bashrc', 'direct edit\n')
  H.start(child, ctx.home)
  H.setup(child)
  write_buf(ctx.src .. '/dot_bashrc', { 'export A=2' })
  local note = H.wait_note(child, '~/.bashrc has changed since chezmoi last wrote it')
  eq(note.level, vim.log.levels.ERROR)
  eq(H.read(ctx.home .. '/.bashrc'), 'direct edit\n')
end

return T
