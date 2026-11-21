-- Test helpers: a child Neovim with an isolated HOME and a seeded chezmoi source dir.
local H = {}

H.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

local ENV_VARS = {
  'HOME',
  'XDG_CONFIG_HOME',
  'XDG_DATA_HOME',
  'XDG_STATE_HOME',
  'XDG_CACHE_HOME',
  'CHEZMOI_NVIM_CHILD',
}

local SEED = {
  ['dot_bashrc'] = 'export A=1\n',
  ['dot_gitconfig.tmpl'] = '[user]\n\tname = {{ "test" }}\n',
  ['run_onchange_install.sh'] = '#!/bin/sh\ntouch "$HOME/script-ran"\n',
}

---@param path string
---@param content string
function H.write(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local file = assert(io.open(path, 'w'))
  file:write(content)
  file:close()
end

---@param path string
---@return string?
function H.read(path)
  local file = io.open(path, 'r')
  if not file then
    return nil
  end
  local content = file:read('*a')
  file:close()
  return content
end

---Create a fresh HOME with a seeded source dir. Returns paths.
---@return { home: string, src: string }
function H.new_home()
  local home = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(home, 'p')
  home = vim.fs.normalize(assert(vim.uv.fs_realpath(home)))
  local src = home .. '/.local/share/chezmoi'
  for name, content in pairs(SEED) do
    H.write(src .. '/' .. name, content)
  end
  return { home = home, src = src }
end

---Environment for processes that must only see `home`.
---@param home string
---@return table<string, string>
function H.env(home)
  return {
    HOME = home,
    XDG_CONFIG_HOME = home .. '/.config',
    XDG_DATA_HOME = home .. '/.local/share',
    XDG_STATE_HOME = home .. '/.local/state',
    XDG_CACHE_HOME = home .. '/.cache',
    CHEZMOI_NVIM_CHILD = '1',
  }
end

---Run chezmoi synchronously in the test process against `home` (test setup only).
---@param home string
---@param args string[]
---@return vim.SystemCompleted
function H.chezmoi(home, args)
  local argv = { 'chezmoi', '--no-tty' }
  vim.list_extend(argv, args)
  return vim.system(argv, { env = H.env(home), text = true }):wait(10000)
end

---Start `child` with HOME/XDG pointing at `home`, minimal_init and captured notifications.
---@param child table MiniTest child
---@param home string
---@param args? string[] extra nvim arguments
function H.start(child, home, args)
  local saved = {}
  for _, name in ipairs(ENV_VARS) do
    saved[name] = vim.env[name]
  end
  for name, value in pairs(H.env(home)) do
    vim.env[name] = value
  end
  local ok, err =
    pcall(child.start, vim.list_extend({ '-u', H.root .. '/tests/minimal_init.lua' }, args or {}))
  for _, name in ipairs(ENV_VARS) do
    vim.env[name] = saved[name]
  end
  assert(ok, err)
  child.lua([[
    _G.notes = {}
    vim.notify = function(msg, level)
      table.insert(_G.notes, { msg = msg, level = level or vim.log.levels.INFO })
    end
  ]])
end

---Wait in the child until `expr` (Lua expression) is truthy. Fails the test on timeout.
---@param child table
---@param expr string
---@param timeout? integer
function H.wait(child, expr, timeout)
  local ok = child.lua_get(
    ('vim.wait(%d, function() return (%s) and true or false end, 10)'):format(timeout or 5000, expr)
  )
  if not ok then
    error('timed out waiting for: ' .. expr, 2)
  end
end

---Call setup() in the child and wait until the index is ready.
---@param child table
---@param opts? table
function H.setup(child, opts)
  child.lua('require("chezmoi").setup(...)', { opts or {} })
  H.wait(child, 'require("chezmoi.index").ready')
end

---Notifications captured in the child.
---@param child table
---@return { msg: string, level: integer }[]
function H.notes(child)
  return child.lua_get('_G.notes')
end

---Wait until a notification matching `pattern` (plain text) appears; return it.
---@param child table
---@param text string
---@return { msg: string, level: integer }
function H.wait_note(child, text)
  H.wait(
    child,
    ('vim.iter(_G.notes):any(function(note) return note.msg:find(%q, 1, true) ~= nil end)'):format(
      text
    )
  )
  for _, note in ipairs(H.notes(child)) do
    if note.msg:find(text, 1, true) then
      return note
    end
  end
  error('unreachable')
end

---Name of the buffer in the current window of the child.
function H.bufname(child)
  return child.lua_get('vim.api.nvim_buf_get_name(0)')
end

---A test set with a fresh child and HOME per case.
---@return table set, table child, table ctx ctx.home and ctx.src are set per case
function H.new_set()
  local child = MiniTest.new_child_neovim()
  local ctx = {}
  local set = MiniTest.new_set({
    hooks = {
      pre_case = function()
        local paths = H.new_home()
        ctx.home, ctx.src = paths.home, paths.src
      end,
      post_case = function()
        child.stop()
        if ctx.home then
          vim.fn.delete(ctx.home, 'rf')
        end
      end,
    },
  })
  return set, child, ctx
end

return H
