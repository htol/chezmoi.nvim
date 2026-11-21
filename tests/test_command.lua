local H = require('tests.helpers')
local eq = MiniTest.expect.equality

local T, child, ctx = H.new_set()

local function edit(path)
  child.lua('vim.cmd.edit(vim.fn.fnameescape(...))', { path })
end

local function managed()
  local res = H.chezmoi(ctx.home, { 'managed', '--include=files' })
  return vim.split(vim.trim(res.stdout), '\n', { trimempty = true })
end

---Answer the next vim.ui.select with the item at position `choice_index`.
local function answer(choice_index)
  child.lua(
    [[
    local choice_index = ...
    vim.ui.select = function(items, opts, on_choice)
      _G.asked = opts.prompt
      _G.items = items
      on_choice(items[choice_index], choice_index)
    end
  ]],
    { choice_index }
  )
end

T['completion lists subcommands and aliases'] = function()
  H.start(child, ctx.home)
  eq(
    child.lua_get('vim.fn.getcompletion("Chezmoi ", "cmdline")'),
    { 'add', 'apply', 'forget', 'manage', 'refresh', 'unmanage' }
  )
  eq(child.lua_get('vim.fn.getcompletion("Chezmoi ma", "cmdline")'), { 'manage' })
  eq(child.lua_get('vim.fn.getcompletion("Chezmoi manage --te", "cmdline")'), { '--template' })
end

T['unknown subcommand lists the valid ones'] = function()
  H.start(child, ctx.home)
  child.cmd('Chezmoi frobnicate')
  local notes = H.notes(child)
  eq(#notes, 1)
  eq(notes[1].level, vim.log.levels.ERROR)
  MiniTest.expect.no_equality(
    notes[1].msg:find('add, apply, forget, manage, refresh, unmanage', 1, true),
    nil
  )
end

T['missing subcommand is an error'] = function()
  H.start(child, ctx.home)
  child.cmd('Chezmoi')
  eq(H.notes(child)[1].level, vim.log.levels.ERROR)
end

T['first use runs setup lazily'] = function()
  H.start(child, ctx.home)
  eq(child.lua_get('require("chezmoi").did_setup()'), false)
  child.cmd('Chezmoi refresh')
  H.wait_note(child, 'index rebuilt, 2 managed files')
  eq(child.lua_get('require("chezmoi").did_setup()'), true)
end

T['add an unmanaged file'] = function()
  H.write(ctx.home .. '/.inputrc', 'set bell-style none\n')
  H.start(child, ctx.home)
  H.setup(child)
  edit(ctx.home .. '/.inputrc')
  child.cmd('Chezmoi add')
  H.wait_note(child, 'added ~/.inputrc')
  eq(H.bufname(child), ctx.src .. '/dot_inputrc')
  eq(vim.tbl_contains(managed(), '.inputrc'), true)
  eq(child.lua_get('vim.fn.bufnr(...)', { ctx.home .. '/.inputrc' }), -1)
end

T['manage --template creates a template source'] = function()
  H.write(ctx.home .. '/.inputrc', 'set bell-style none\n')
  H.start(child, ctx.home)
  H.setup(child)
  edit(ctx.home .. '/.inputrc')
  child.cmd('Chezmoi manage --template')
  H.wait_note(child, 'added ~/.inputrc')
  eq(H.bufname(child), ctx.src .. '/dot_inputrc.tmpl')
end

T['add refuses an unsaved buffer'] = function()
  H.write(ctx.home .. '/.inputrc', 'set bell-style none\n')
  H.start(child, ctx.home)
  H.setup(child)
  edit(ctx.home .. '/.inputrc')
  child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed" })')
  child.cmd('Chezmoi add')
  local note = H.wait_note(child, 'save it first')
  eq(note.level, vim.log.levels.ERROR)
  vim.uv.sleep(300)
  eq(vim.tbl_contains(managed(), '.inputrc'), false)
end

T['add refuses an already managed file'] = function()
  H.start(child, ctx.home)
  H.setup(child)
  edit(ctx.src .. '/dot_bashrc')
  child.cmd('Chezmoi add')
  local note = H.wait_note(child, 'is already managed')
  eq(note.level, vim.log.levels.ERROR)
end

T['forget from the source buffer'] = function()
  H.write(ctx.src .. '/dot_inputrc', 'set bell-style none\n')
  H.chezmoi(ctx.home, { 'apply' })
  H.start(child, ctx.home)
  H.setup(child)
  edit(ctx.src .. '/dot_inputrc')
  answer(2)
  child.cmd('Chezmoi forget')
  H.wait_note(child, 'stopped managing ~/.inputrc')
  eq(child.lua_get('_G.items'), { 'No', 'Yes, delete source dot_inputrc' })
  eq(child.lua_get('_G.asked'), 'Forget ~/.inputrc?')
  eq(vim.tbl_contains(managed(), '.inputrc'), false)
  eq(H.read(ctx.home .. '/.inputrc'), 'set bell-style none\n')
  eq(vim.uv.fs_stat(ctx.src .. '/dot_inputrc'), nil)
  eq(H.bufname(child), ctx.home .. '/.inputrc')
  eq(child.lua_get('vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'set bell-style none' })
end

T['user declines unmanage'] = function()
  H.write(ctx.src .. '/dot_inputrc', 'set bell-style none\n')
  H.start(child, ctx.home)
  H.setup(child)
  edit(ctx.src .. '/dot_inputrc')
  answer(1)
  child.cmd('Chezmoi unmanage')
  H.wait(child, '_G.asked ~= nil')
  vim.uv.sleep(300)
  eq(vim.tbl_contains(managed(), '.inputrc'), true)
  eq(H.bufname(child), ctx.src .. '/dot_inputrc')
  eq(H.notes(child), {})
end

T['forget refuses an unmanaged buffer'] = function()
  H.write(ctx.home .. '/notes.txt', 'x\n')
  H.start(child, ctx.home)
  H.setup(child)
  edit(ctx.home .. '/notes.txt')
  child.cmd('Chezmoi forget')
  eq(H.wait_note(child, 'is not managed').level, vim.log.levels.ERROR)
end

T['manual apply with apply_on_save disabled'] = function()
  H.start(child, ctx.home)
  H.setup(child, { apply_on_save = false })
  edit(ctx.src .. '/dot_bashrc')
  child.cmd('Chezmoi apply')
  eq(H.wait_note(child, 'applied ~/.bashrc').level, vim.log.levels.INFO)
  eq(H.read(ctx.home .. '/.bashrc'), 'export A=1\n')
end

T['apply refuses an unmanaged buffer'] = function()
  H.start(child, ctx.home)
  H.setup(child)
  child.cmd('Chezmoi apply')
  eq(H.wait_note(child, 'is not managed').level, vim.log.levels.ERROR)
end

T['refresh picks up a file added from the shell'] = function()
  H.write(ctx.home .. '/.inputrc', 'set bell-style none\n')
  H.start(child, ctx.home)
  H.setup(child)
  eq(H.chezmoi(ctx.home, { 'add', ctx.home .. '/.inputrc' }).code, 0)
  child.cmd('Chezmoi refresh')
  H.wait_note(child, 'index rebuilt, 3 managed files')
  edit(ctx.home .. '/.inputrc')
  H.wait(child, ('vim.api.nvim_buf_get_name(0) == %q'):format(ctx.src .. '/dot_inputrc'))
end

return T
