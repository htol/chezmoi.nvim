local runner = require('chezmoi.runner')

local M = {}

local group = vim.api.nvim_create_augroup('chezmoi.preview', { clear = true })

---@class chezmoi.PreviewState
---@field target string
---@field generation integer number of the latest render request
---@field buf? integer preview buffer, created by the first successful render
---@field tick? integer source changedtick of the last successful render

local states = {} ---@type table<integer, chezmoi.PreviewState> source buffer -> state

local function home(path)
  return vim.fn.fnamemodify(path, ':~')
end

---Source buffer text as it would be written to disk.
---@param buf integer
---@return string
local function buffer_text(buf)
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  if vim.bo[buf].eol then
    text = text .. '\n'
  end
  return text
end

---Show the target and the stale mark in every window of the preview.
---@param source_buf integer
---@param state chezmoi.PreviewState
local function update_winbar(source_buf, state)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  -- Defined here rather than once: a :colorscheme clears it.
  vim.api.nvim_set_hl(0, 'ChezmoiPreviewStale', { link = 'WarningMsg', default = true })
  local stale = state.tick ~= vim.api.nvim_buf_get_changedtick(source_buf)
  local bar = ' preview: ' .. (home(state.target):gsub('%%', '%%%%'))
  if stale then
    bar = bar .. ' %#ChezmoiPreviewStale#[stale]%*'
  end
  for _, win in ipairs(vim.fn.win_findbuf(state.buf)) do
    vim.api.nvim_set_option_value('winbar', bar, { scope = 'local', win = win })
  end
end

---Forget the preview of `source_buf` and stop refreshing it, if `state` is still its preview.
---@param source_buf integer
---@param state chezmoi.PreviewState
local function cleanup(source_buf, state)
  if states[source_buf] ~= state then
    return
  end
  states[source_buf] = nil
  if vim.api.nvim_buf_is_valid(source_buf) then
    vim.api.nvim_clear_autocmds({ group = group, buffer = source_buf })
  end
end

local render

---Create the preview buffer and the autocmds that keep it in sync with its source.
---@param source_buf integer
---@param state chezmoi.PreviewState
---@return integer buf
local function create_buffer(source_buf, state)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, 'chezmoi://preview/' .. home(state.target))
  state.buf = buf

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    buffer = buf,
    callback = function()
      cleanup(source_buf, state)
    end,
    desc = 'chezmoi: stop refreshing a closed preview',
  })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = group,
    buffer = source_buf,
    callback = function()
      update_winbar(source_buf, state)
    end,
    desc = 'chezmoi: mark the preview stale',
  })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    buffer = source_buf,
    callback = function()
      render(source_buf, state, false)
    end,
    desc = 'chezmoi: re-render the preview',
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    buffer = source_buf,
    callback = function()
      cleanup(source_buf, state)
      -- Deleting another buffer from inside a wipeout is not safe; do it afterwards.
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end)
    end,
    desc = 'chezmoi: close the preview of a wiped source',
  })
  return buf
end

---Open a vertical split with the preview next to the source, without entering it.
---@param source_buf integer
---@param buf integer
---@param origin_win integer window that was current when the render was requested
local function open_window(source_buf, buf, origin_win)
  local win = origin_win
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= source_buf then
    win = vim.fn.win_findbuf(source_buf)[1]
  end
  local win_config = { vertical = true } ---@type vim.api.keyset.win_config
  if win then
    win_config.win = win
  end
  vim.api.nvim_open_win(buf, false, win_config)
end

---Render the source buffer through chezmoi into its preview. Only the latest request is applied.
---@param source_buf integer
---@param state chezmoi.PreviewState
---@param show boolean open a window when the preview is not shown
function render(source_buf, state, show)
  state.generation = state.generation + 1
  local generation = state.generation
  -- Captured with the text, so edits made while chezmoi runs leave the preview stale.
  local tick = vim.api.nvim_buf_get_changedtick(source_buf)
  local origin_win = vim.api.nvim_get_current_win()

  runner.run({ 'execute-template' }, function(res)
    if states[source_buf] ~= state or state.generation ~= generation then
      return
    end
    if not res.ok then
      vim.notify(
        ('chezmoi: rendering %s failed:\n%s'):format(home(state.target), res.stderr),
        vim.log.levels.ERROR
      )
      if state.buf then
        state.tick = nil
        update_winbar(source_buf, state)
      else
        states[source_buf] = nil
      end
      return
    end

    local lines = vim.split(res.stdout, '\n', { plain = true })
    if lines[#lines] == '' then
      table.remove(lines)
    end
    local first = state.buf == nil
    local buf = state.buf or create_buffer(source_buf, state)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    if first then
      local ft = vim.filetype.match({ filename = state.target, buf = buf })
      if ft then
        vim.bo[buf].filetype = ft
      end
    end
    state.tick = tick
    if show and #vim.fn.win_findbuf(buf) == 0 then
      open_window(source_buf, buf, origin_win)
    end
    update_winbar(source_buf, state)
  end, { stdin = buffer_text(source_buf) })
end

---Render `source_buf`, including unsaved changes, and show the result next to it. The window
---opens after the first successful render; later calls re-render into the same window.
---@param source_buf integer buffer of a managed template source
---@param target string absolute target path of that source
function M.open(source_buf, target)
  local state = states[source_buf]
  if not state then
    state = { target = target, generation = 0 }
    states[source_buf] = state
  end
  render(source_buf, state, true)
end

return M
