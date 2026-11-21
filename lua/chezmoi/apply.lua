local config = require('chezmoi.config')
local index = require('chezmoi.index')
local runner = require('chezmoi.runner')

local M = {}

local group = vim.api.nvim_create_augroup('chezmoi.apply', { clear = true })

-- Per target: at most one running apply and one pending.
local queue = {} ---@type table<string, { pending: boolean }>

local CONFLICT = 'has changed since chezmoi last wrote it'

---@param target string
---@param res chezmoi.Result
local function report(target, res)
  local name = vim.fn.fnamemodify(target, ':~')
  if res.ok then
    vim.notify('chezmoi: applied ' .. name, vim.log.levels.INFO)
  elseif res.stdout:find(CONFLICT, 1, true) then
    -- With --no-tty and stdin closed, chezmoi prints the overwrite prompt on stdout and fails.
    vim.notify(
      ('chezmoi: %s %s; not overwritten. Resolve it with `chezmoi diff` or `chezmoi merge` in a shell'):format(
        name,
        CONFLICT
      ),
      vim.log.levels.ERROR
    )
  else
    vim.notify(('chezmoi: applying %s failed:\n%s'):format(name, res.stderr), vim.log.levels.ERROR)
  end
end

---Apply one target asynchronously. A call while an apply of the same target is running is
---queued; further calls replace the queued one.
---@param target string absolute target path
function M.apply(target)
  local entry = queue[target]
  if entry then
    entry.pending = true
    return
  end
  entry = { pending = false }
  queue[target] = entry
  runner.run({ 'apply', target }, function(res)
    report(target, res)
    queue[target] = nil
    if entry.pending then
      M.apply(target)
    end
  end)
end

local function on_write(args)
  local path = vim.api.nvim_buf_get_name(args.buf)
  if not index.ready or not index.in_source_dir(path) then
    return
  end
  local target = index.target_of(path)
  if target then
    if config.options.apply_on_save then
      M.apply(target)
    end
  else
    -- Scripts, .chezmoiignore, data and templates: never applied, but may change the index.
    index.build()
  end
end

function M.setup()
  vim.api.nvim_clear_autocmds({ group = group })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    callback = on_write,
    desc = 'chezmoi: apply the target of a written source',
  })
end

return M
