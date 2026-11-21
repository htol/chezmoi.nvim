local config = require('chezmoi.config')
local index = require('chezmoi.index')

local M = {}

local group = vim.api.nvim_create_augroup('chezmoi.redirect', { clear = true })

---Escape a path for use as an autocmd file pattern.
---@param path string
---@return string
local function pattern_escape(path)
  return (path:gsub('[%[%]{}*?,\\]', '\\%0'))
end

---Show `source` in every window that shows `target_buf`, then wipe `target_buf`.
---The source buffer gets the filetype of `target`.
---@param target_buf integer
---@param target string
---@param source string
function M.show_source(target_buf, target, source)
  local src_buf = vim.fn.bufadd(source)
  for _, win in ipairs(vim.fn.win_findbuf(target_buf)) do
    vim.api.nvim_win_call(win, function()
      vim.cmd('keepalt keepjumps buffer ' .. src_buf)
    end)
  end
  if src_buf ~= target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    vim.api.nvim_buf_delete(target_buf, { force = true })
  end
  if vim.api.nvim_buf_is_loaded(src_buf) then
    local ft = vim.filetype.match({ filename = target })
    if ft then
      vim.bo[src_buf].filetype = ft
    end
  end
end

---Read `path` into `buf` the way :edit would, for a target the index no longer knows.
local function read_normally(buf, path)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd('silent keepalt read ++edit ' .. vim.fn.fnameescape(path))
    vim.cmd('silent 1delete _')
    vim.bo[buf].modified = false
    vim.api.nvim_exec_autocmds('BufReadPost', { buffer = buf, modeline = true })
  end)
end

local function on_read_cmd(args)
  local buf, target = args.buf, args.match
  local source = index.source_of(target)
  if not source then
    read_normally(buf, target)
    return
  end
  -- Switching buffers inside BufReadCmd would race with the :edit that triggered it.
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(buf) then
      M.show_source(buf, target, source)
    end
  end)
end

local function define_autocmds()
  vim.api.nvim_clear_autocmds({ group = group })
  if not config.options.redirect or not index.ready then
    return
  end
  local patterns = vim.tbl_map(pattern_escape, index.targets())
  if #patterns == 0 then
    return
  end
  vim.api.nvim_create_autocmd('BufReadCmd', {
    group = group,
    pattern = patterns,
    callback = on_read_cmd,
    desc = 'chezmoi: open the source of a managed target',
  })
end

---Redirect target buffers that were loaded before the index was ready.
local function sweep()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' then
      local target = vim.api.nvim_buf_get_name(buf)
      local source = index.source_of(target)
      if source then
        if vim.bo[buf].modified then
          vim.notify(
            ('chezmoi: %s is a chezmoi target with unsaved changes; edit %s instead'):format(
              vim.fn.fnamemodify(target, ':~'),
              vim.fn.fnamemodify(source, ':~')
            ),
            vim.log.levels.WARN
          )
        else
          M.show_source(buf, target, source)
        end
      end
    end
  end
end

function M.setup()
  define_autocmds()
end

index.on_change(function(became_ready)
  define_autocmds()
  if became_ready and config.options.redirect then
    sweep()
  end
end)

return M
