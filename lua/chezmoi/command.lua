local index = require('chezmoi.index')
local runner = require('chezmoi.runner')

local M = {}

local function err(msg)
  vim.notify('chezmoi: ' .. msg, vim.log.levels.ERROR)
end

local function info(msg)
  vim.notify('chezmoi: ' .. msg, vim.log.levels.INFO)
end

local function home(path)
  return vim.fn.fnamemodify(path, ':~')
end

---The current buffer's file, or nil after reporting why it cannot be used.
---@return integer? buf, string? path
local function current_file()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if path == '' or vim.bo[buf].buftype ~= '' then
    err('the current buffer has no file')
    return nil
  end
  if vim.bo[buf].modified then
    err('the buffer has unsaved changes; save it first')
    return nil
  end
  return buf, path
end

---Target of the current buffer, whether it shows the target or its source.
---@param path string
---@return string?
local function target_for(path)
  if index.source_of(path) then
    return vim.fs.normalize(vim.fs.abspath(path))
  end
  return index.target_of(path)
end

---Run `fn` once the index is ready; report a failed build instead.
local function with_index(fn)
  index.wait(function(ok, msg)
    if ok then
      fn()
    else
      err(msg or 'the index is not available')
    end
  end)
end

local function add(args)
  local buf, path = current_file()
  if not buf or not path then
    return
  end
  with_index(function()
    if index.is_managed(path) then
      err(home(path) .. ' is already managed')
      return
    end
    local argv = { 'add' }
    vim.list_extend(argv, args)
    argv[#argv + 1] = path
    runner.run(argv, function(res)
      if not res.ok then
        err('adding ' .. home(path) .. ' failed:\n' .. res.stderr)
        return
      end
      index.build(function()
        local source = index.source_of(path)
        if source and vim.api.nvim_buf_is_valid(buf) then
          require('chezmoi.redirect').show_source(buf, path, source)
        end
        info('added ' .. home(path))
      end)
    end)
  end)
end

local function forget()
  local buf, path = current_file()
  if not buf or not path then
    return
  end
  with_index(function()
    local target = target_for(path)
    if not target then
      err(home(path) .. ' is not managed')
      return
    end
    local source = index.source_of(target)
    -- Pickers may truncate the prompt to one line, so what gets deleted is in the item text.
    -- 'No' comes first so that a reflexive <CR> deletes nothing.
    local rel = index.source_dir and source and vim.fs.relpath(index.source_dir, source)
    local yes = 'Yes, delete source ' .. (rel or home(source))
    vim.ui.select({ 'No', yes }, {
      prompt = ('Forget %s?'):format(home(target)),
    }, function(choice)
      if choice ~= yes then
        return
      end
      runner.run({ 'forget', '--force', target }, function(res)
        if not res.ok then
          err('forgetting ' .. home(target) .. ' failed:\n' .. res.stderr)
          return
        end
        index.build(function()
          local src_buf = vim.fn.bufnr(source)
          if src_buf ~= -1 then
            for _, win in ipairs(vim.fn.win_findbuf(src_buf)) do
              vim.api.nvim_win_call(win, function()
                vim.cmd('keepalt edit ' .. vim.fn.fnameescape(target))
              end)
            end
            if vim.api.nvim_buf_is_valid(src_buf) then
              vim.api.nvim_buf_delete(src_buf, { force = true })
            end
          end
          info('stopped managing ' .. home(target))
        end)
      end)
    end)
  end)
end

local function apply()
  local path = vim.api.nvim_buf_get_name(0)
  with_index(function()
    local target = target_for(path)
    if not target then
      err((path == '' and 'the current buffer' or home(path)) .. ' is not managed')
      return
    end
    require('chezmoi.apply').apply(target)
  end)
end

local function preview()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.bo[buf].buftype == '' and vim.api.nvim_buf_get_name(buf) or ''
  with_index(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local target = path ~= '' and index.target_of(path) or nil
    if target then
      if (index.source_of(target) or path):match('%.tmpl$') then
        require('chezmoi.preview').open(buf, target)
      else
        info(home(target) .. ' is not a template; its source is copied as is')
      end
      return
    end
    local source = path ~= '' and index.source_of(path) or nil
    if source then
      if source:match('%.tmpl$') then
        info(home(path) .. ' is a target; preview its template ' .. home(source))
      else
        info(home(path) .. ' is not a template; its source is copied as is')
      end
      return
    end
    info((path == '' and 'the current buffer' or home(path)) .. ' is not managed by chezmoi')
  end)
end

local function refresh()
  index.build(function(ok, msg)
    if ok then
      info(('index rebuilt, %d managed files'):format(index.count))
    else
      err(msg or 'rebuilding the index failed')
    end
  end, { quiet = true })
end

---@class chezmoi.Subcommand
---@field run? fun(args: string[], opts: table)
---@field complete? fun(arglead: string): string[]
---@field alias_of? string

---@type table<string, chezmoi.Subcommand>
M.subcommands = {
  add = {
    run = add,
    complete = function()
      return { '--template', '--follow', '--exact', '--create' }
    end,
  },
  manage = { alias_of = 'add' },
  forget = { run = forget },
  unmanage = { alias_of = 'forget' },
  apply = { run = apply },
  preview = { run = preview },
  refresh = { run = refresh },
}

---@return string[]
local function names()
  local list = vim.tbl_keys(M.subcommands)
  table.sort(list)
  return list
end

---@param name string
---@return chezmoi.Subcommand?
local function resolve(name)
  local sub = M.subcommands[name]
  if sub and sub.alias_of then
    sub = M.subcommands[sub.alias_of]
  end
  return sub
end

---Handler for :Chezmoi.
---@param opts table nvim_create_user_command callback argument
function M.dispatch(opts)
  local name = opts.fargs[1]
  local sub = name and resolve(name)
  if not sub or not sub.run then
    local what = name and ("unknown subcommand '" .. name .. "'") or 'missing subcommand'
    err(what .. '; valid subcommands: ' .. table.concat(names(), ', '))
    return
  end
  require('chezmoi').ensure_setup()
  sub.run(vim.list_slice(opts.fargs, 2), opts)
end

---Completion for :Chezmoi.
---@param arglead string
---@param cmdline string
---@param pos integer
---@return string[]
function M.complete(arglead, cmdline, pos)
  local words = vim.split(cmdline:sub(1, pos), '%s+', { trimempty = true })
  local nargs = #words - 1 -- without the command name
  if arglead == '' then
    nargs = nargs + 1
  end
  local candidates = {}
  if nargs <= 1 then
    candidates = names()
  else
    local sub = resolve(words[2])
    candidates = sub and sub.complete and sub.complete(arglead) or {}
  end
  return vim.tbl_filter(function(candidate)
    return vim.startswith(candidate, arglead)
  end, candidates)
end

return M
