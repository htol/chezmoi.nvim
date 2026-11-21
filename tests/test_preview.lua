local H = require('tests.helpers')
local eq = MiniTest.expect.equality

local T, child, ctx = H.new_set()

local function edit(path)
  child.lua('vim.cmd.edit(vim.fn.fnameescape(...))', { path })
end

---Start the child, set up the plugin, open the template source and count chezmoi processes.
---@param opts? table setup options
local function start(opts)
  H.start(child, ctx.home)
  H.setup(child, opts)
  child.lua([[
    _G.pbuf = function()
      return vim.iter(vim.api.nvim_list_bufs()):find(function(buf)
        return vim.api.nvim_buf_get_name(buf):find('^chezmoi://preview/') ~= nil
      end)
    end
    _G.plines = function()
      return vim.api.nvim_buf_get_lines(_G.pbuf(), 0, -1, false)
    end
    _G.pwin = function()
      return vim.fn.win_findbuf(_G.pbuf() or -1)[1]
    end
    _G.winbar = function()
      return vim.api.nvim_get_option_value('winbar', { win = _G.pwin() })
    end
    local runner = require('chezmoi.runner')
    local run = runner.run
    _G.started, _G.finished = 0, 0
    runner.run = function(args, cb, run_opts)
      _G.started = _G.started + 1
      run(args, function(res)
        _G.finished = _G.finished + 1
        cb(res)
      end, run_opts)
    end
  ]])
end

local function set_name_line(text)
  child.lua('vim.api.nvim_buf_set_lines(0, 1, 2, false, { ... })', { text })
end

local function wait_line(text)
  H.wait(child, ('_G.pbuf() and _G.plines()[2] == %q'):format(text))
end

local function window_count()
  return child.lua_get('#vim.api.nvim_tabpage_list_wins(0)')
end

local function stale()
  return child.lua_get('_G.winbar():find("[stale]", 1, true) ~= nil')
end

T['saved template renders into a read-only split'] = function()
  start()
  edit(ctx.src .. '/dot_gitconfig.tmpl')
  local source_win = child.lua_get('vim.api.nvim_get_current_win()')
  child.cmd('Chezmoi preview')
  wait_line('\tname = test')
  eq(child.lua_get('_G.plines()'), { '[user]', '\tname = test' })
  eq(child.lua_get('vim.bo[_G.pbuf()].modifiable'), false)
  eq(child.lua_get('vim.bo[_G.pbuf()].buftype'), 'nofile')
  eq(child.lua_get('vim.bo[_G.pbuf()].filetype'), 'gitconfig')
  eq(child.lua_get('vim.api.nvim_get_current_win()'), source_win)
  eq(window_count(), 2)
  -- Vertical split: both windows span the full height.
  eq(
    child.lua_get('vim.api.nvim_win_get_height(_G.pwin())'),
    child.lua_get('vim.api.nvim_win_get_height(0)')
  )
end

T['repeated command reuses the window'] = function()
  start()
  edit(ctx.src .. '/dot_gitconfig.tmpl')
  child.cmd('Chezmoi preview')
  wait_line('\tname = test')
  set_name_line('\tname = {{ "other" }}')
  child.cmd('Chezmoi preview')
  wait_line('\tname = other')
  eq(window_count(), 2)
end

T['unsaved edits are rendered, nothing is written'] = function()
  start()
  edit(ctx.src .. '/dot_gitconfig.tmpl')
  set_name_line('\tname = {{ "other" }}')
  child.cmd('Chezmoi preview')
  wait_line('\tname = other')
  eq(H.read(ctx.src .. '/dot_gitconfig.tmpl'), '[user]\n\tname = {{ "test" }}\n')
  eq(H.read(ctx.home .. '/.gitconfig'), nil)
end

T['only the latest of overlapping renders is applied'] = function()
  start()
  edit(ctx.src .. '/dot_gitconfig.tmpl')
  child.lua([[
    -- Deliver the first result after the second one.
    local runner = require('chezmoi.runner')
    local run = runner.run
    local calls = 0
    runner.run = function(args, cb, run_opts)
      calls = calls + 1
      local delay = calls == 1 and 300 or 0
      run(args, function(res)
        vim.defer_fn(function()
          _G.delivered = (_G.delivered or 0) + 1
          cb(res)
        end, delay)
      end, run_opts)
    end
    vim.api.nvim_buf_set_lines(0, 1, 2, false, { '\tname = {{ "first" }}' })
    vim.cmd('Chezmoi preview')
    vim.api.nvim_buf_set_lines(0, 1, 2, false, { '\tname = {{ "second" }}' })
    vim.cmd('Chezmoi preview')
  ]])
  H.wait(child, '_G.delivered == 2')
  eq(child.lua_get('_G.plines()'), { '[user]', '\tname = second' })
  eq(stale(), false)
end

T['broken template without a preview: error, no window'] = function()
  start()
  edit(ctx.src .. '/dot_gitconfig.tmpl')
  set_name_line('{{ if')
  child.cmd('Chezmoi preview')
  local note = H.wait_note(child, 'rendering ~/.gitconfig failed')
  eq(note.level, vim.log.levels.ERROR)
  MiniTest.expect.no_equality(note.msg:find('unclosed action', 1, true), nil)
  eq(window_count(), 1)
  eq(child.lua_get('_G.pbuf()'), vim.NIL)
end

T['broken template with a preview: error, content kept, stale'] = function()
  start()
  edit(ctx.src .. '/dot_gitconfig.tmpl')
  child.cmd('Chezmoi preview')
  wait_line('\tname = test')
  set_name_line('{{ if')
  child.cmd('Chezmoi preview')
  local note = H.wait_note(child, 'rendering ~/.gitconfig failed')
  MiniTest.expect.no_equality(note.msg:find('unclosed action', 1, true), nil)
  eq(child.lua_get('_G.plines()'), { '[user]', '\tname = test' })
  eq(stale(), true)
end

T['an edit marks the preview stale without running chezmoi'] = function()
  start()
  edit(ctx.src .. '/dot_gitconfig.tmpl')
  child.cmd('Chezmoi preview')
  wait_line('\tname = test')
  eq(child.lua_get('_G.winbar():find("~/.gitconfig", 1, true) ~= nil'), true)
  eq(stale(), false)
  local started = child.lua_get('_G.started')
  child.type_keys('G', 'o', 'x', '<Esc>')
  H.wait(child, '_G.winbar():find("[stale]", 1, true) ~= nil')
  vim.uv.sleep(200)
  eq(child.lua_get('_G.started'), started)
  eq(child.lua_get('vim.api.nvim_get_hl(0, { name = "ChezmoiPreviewStale" }).link'), 'WarningMsg')

  child.cmd('Chezmoi preview')
  H.wait(child, '_G.winbar():find("[stale]", 1, true) == nil')
end

T['write re-renders regardless of apply_on_save'] = function()
  start({ apply_on_save = false })
  edit(ctx.src .. '/dot_gitconfig.tmpl')
  child.cmd('Chezmoi preview')
  wait_line('\tname = test')
  set_name_line('\tname = {{ "other" }}')
  child.cmd('write')
  wait_line('\tname = other')
  eq(stale(), false)
  eq(H.read(ctx.home .. '/.gitconfig'), nil)
end

T['closed preview stays closed and leaves no autocmds'] = function()
  start({ apply_on_save = false })
  edit(ctx.src .. '/dot_gitconfig.tmpl')
  child.cmd('Chezmoi preview')
  wait_line('\tname = test')
  child.lua('vim.api.nvim_win_close(_G.pwin(), true)')
  eq(child.lua_get('_G.pbuf()'), vim.NIL)
  eq(child.lua_get('#vim.api.nvim_get_autocmds({ group = "chezmoi.preview" })'), 0)
  local started = child.lua_get('_G.started')
  set_name_line('\tname = {{ "other" }}')
  child.cmd('write')
  vim.uv.sleep(300)
  eq(child.lua_get('_G.started'), started)
  eq(window_count(), 1)
end

T['managed source that is not a template'] = function()
  start()
  edit(ctx.src .. '/dot_bashrc')
  child.cmd('Chezmoi preview')
  local note = H.wait_note(child, '~/.bashrc is not a template')
  eq(note.level, vim.log.levels.INFO)
  eq(window_count(), 1)
end

T['unmanaged file'] = function()
  H.write(ctx.home .. '/notes.txt', 'x\n')
  start()
  edit(ctx.home .. '/notes.txt')
  child.cmd('Chezmoi preview')
  local note = H.wait_note(child, '~/notes.txt is not managed by chezmoi')
  eq(note.level, vim.log.levels.INFO)
  eq(window_count(), 1)
end

T['buffer without a file'] = function()
  start()
  child.cmd('Chezmoi preview')
  local note = H.wait_note(child, 'the current buffer is not managed by chezmoi')
  eq(note.level, vim.log.levels.INFO)
  eq(window_count(), 1)
end

T['target buffer with redirect disabled names its source'] = function()
  start({ redirect = false })
  edit(ctx.home .. '/.gitconfig')
  child.cmd('Chezmoi preview')
  local note = H.wait_note(child, 'dot_gitconfig.tmpl')
  eq(note.level, vim.log.levels.INFO)
  MiniTest.expect.no_equality(note.msg:find('~/.gitconfig is a target', 1, true), nil)
  eq(window_count(), 1)
end

return T
