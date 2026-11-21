local H = require('tests.helpers')
local eq = MiniTest.expect.equality

local T, child, ctx = H.new_set()

T['config'] = MiniTest.new_set()

T['config']['defaults'] = function()
  H.start(child, ctx.home)
  eq(
    child.lua_get('require("chezmoi.config").setup()'),
    { cmd = 'chezmoi', redirect = true, apply_on_save = true }
  )
end

T['config']['override'] = function()
  H.start(child, ctx.home)
  eq(
    child.lua_get('require("chezmoi.config").setup({ redirect = false })'),
    { cmd = 'chezmoi', redirect = false, apply_on_save = true }
  )
end

T['config']['rejects a wrong type'] = function()
  H.start(child, ctx.home)
  local res = child.lua_get([[
    { pcall(require("chezmoi.config").setup, { apply_on_save = 'yes' }) }
  ]])
  eq(res[1], false)
  MiniTest.expect.no_equality(res[2]:find('apply_on_save', 1, true), nil)
end

T['runner'] = MiniTest.new_set()

T['runner']['reports exit code and trimmed stderr, asynchronously'] = function()
  H.start(child, ctx.home)
  child.lua([[
    require('chezmoi.config').setup({ cmd = 'sh' })
    _G.res = nil
    require('chezmoi.runner').run({ '-c', 'sleep 0.2; printf "  boom \n\n" >&2; exit 3' }, function(result)
      _G.res = result
    end)
    _G.returned_first = _G.res == nil
  ]])
  eq(child.lua_get('_G.returned_first'), true)
  H.wait(child, '_G.res')
  eq(child.lua_get('{ _G.res.ok, _G.res.code, _G.res.stderr }'), { false, 3, 'boom' })
end

T['runner']['passes stdin to the process'] = function()
  H.start(child, ctx.home)
  child.lua([[
    require('chezmoi.config').setup({ cmd = 'sh' })
    _G.res = nil
    require('chezmoi.runner').run({ '-c', 'tr a-z A-Z' }, function(result)
      _G.res = result
    end, { stdin = 'hello\n' })
  ]])
  H.wait(child, '_G.res')
  eq(child.lua_get('{ _G.res.ok, _G.res.stdout }'), { true, 'HELLO\n' })
end

T['runner']['missing executable is reported through the callback'] = function()
  H.start(child, ctx.home)
  child.lua([[
    require('chezmoi.config').setup({ cmd = 'chezmoi-does-not-exist' })
    _G.res = nil
    require('chezmoi.runner').run({ 'managed' }, function(result) _G.res = result end)
  ]])
  H.wait(child, '_G.res')
  eq(child.lua_get('_G.res.ok'), false)
end

T['index'] = MiniTest.new_set()

T['index']['setup returns before chezmoi exits, index becomes ready'] = function()
  H.start(child, ctx.home)
  eq(
    child.lua_get([[(function()
      require('chezmoi').setup()
      return require('chezmoi.index').ready
    end)()]]),
    false
  )
  H.wait(child, 'require("chezmoi.index").ready')
end

T['index']['plain file'] = function()
  H.start(child, ctx.home)
  H.setup(child)
  eq(
    child.lua_get('require("chezmoi").source_of(...)', { ctx.home .. '/.bashrc' }),
    ctx.src .. '/dot_bashrc'
  )
  eq(
    child.lua_get('require("chezmoi").target_of(...)', { ctx.src .. '/dot_bashrc' }),
    ctx.home .. '/.bashrc'
  )
end

T['index']['template'] = function()
  H.start(child, ctx.home)
  H.setup(child)
  eq(
    child.lua_get('require("chezmoi").source_of("~/.gitconfig")'),
    ctx.src .. '/dot_gitconfig.tmpl'
  )
end

T['index']['scripts are not indexed'] = function()
  H.start(child, ctx.home)
  H.setup(child)
  eq(child.lua_get('require("chezmoi.index").count'), 2)
  eq(
    child.lua_get('require("chezmoi").target_of(...)', { ctx.src .. '/run_onchange_install.sh' }),
    vim.NIL
  )
end

T['index']['encrypted file is excluded'] = function()
  H.write(ctx.src .. '/encrypted_dot_secret.age', 'not really encrypted\n')
  H.start(child, ctx.home)
  H.setup(child)
  eq(child.lua_get('require("chezmoi").source_of("~/.secret")'), vim.NIL)
  eq(child.lua_get('require("chezmoi.index").count'), 2)
end

T['index']['chezmoi missing: inactive with a single warning'] = function()
  H.start(child, ctx.home)
  child.lua('require("chezmoi").setup({ cmd = "chezmoi-does-not-exist" })')
  H.wait(child, '#_G.notes > 0')
  vim.uv.sleep(200)
  local notes = H.notes(child)
  eq(#notes, 1)
  eq(notes[1].level, vim.log.levels.WARN)
  eq(child.lua_get('require("chezmoi.index").ready'), false)
end

T['index']['no source directory: warning with chezmoi message'] = function()
  H.write(ctx.home .. '/.config/chezmoi/chezmoi.toml', 'sourceDir = 1\n')
  H.start(child, ctx.home)
  child.lua('require("chezmoi").setup()')
  H.wait(child, '#_G.notes > 0')
  local notes = H.notes(child)
  eq(#notes, 1)
  eq(notes[1].level, vim.log.levels.WARN)
  MiniTest.expect.no_equality(notes[1].msg:find("'sourceDir' expected a string", 1, true), nil)
  eq(child.lua_get('require("chezmoi.index").ready'), false)
end

T['index']['rebuilds requested during a build are coalesced'] = function()
  H.start(child, ctx.home)
  H.setup(child)
  child.lua([[
    _G.builds = 0
    require('chezmoi.index').on_change(function() _G.builds = _G.builds + 1 end)
    _G.done = 0
    for _ = 1, 5 do
      require('chezmoi.index').build(function() _G.done = _G.done + 1 end)
    end
  ]])
  H.wait(child, '_G.done == 5')
  eq(child.lua_get('_G.builds'), 2)
end

T['api'] = MiniTest.new_set()

T['api']['is_managed is false before the index is ready'] = function()
  H.start(child, ctx.home)
  child.lua('vim.cmd.edit(vim.fn.fnameescape(...))', { ctx.src .. '/dot_bashrc' })
  eq(
    child.lua_get([[(function()
      require('chezmoi').setup()
      return require('chezmoi').is_managed(0)
    end)()]]),
    false
  )
  H.wait(child, 'require("chezmoi.index").ready')
  eq(child.lua_get('require("chezmoi").is_managed(0)'), true)
end

T['api']['source buffer is managed'] = function()
  H.start(child, ctx.home)
  H.setup(child)
  child.lua('vim.cmd.edit(vim.fn.fnameescape(...))', { ctx.src .. '/dot_bashrc' })
  eq(child.lua_get('require("chezmoi").is_managed(0)'), true)
end

T['api']['unmanaged buffer is not managed'] = function()
  H.write(ctx.home .. '/notes.txt', 'x\n')
  H.start(child, ctx.home)
  H.setup(child)
  child.lua('vim.cmd.edit(vim.fn.fnameescape(...))', { ctx.home .. '/notes.txt' })
  eq(child.lua_get('require("chezmoi").is_managed(0)'), false)
end

return T
