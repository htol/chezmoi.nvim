local config = require('chezmoi.config')
local runner = require('chezmoi.runner')

local M = {}

-- Public read-only state.
M.ready = false
---@type string? normalised source directory (realpath)
M.source_dir = nil
---@type string? last build error
M.error = nil
M.count = 0

local by_target = {} ---@type table<string, string> target -> source
local by_source = {} ---@type table<string, string> source -> target
local building = false
local dirty = false
local waiters = {} ---@type fun(ok: boolean, err?: string)[]
local listeners = {} ---@type fun(became_ready: boolean)[]
local warned ---@type string?

---Absolute, normalised path without resolving symlinks.
---@param path string
---@return string
local function normalize(path)
  return vim.fs.normalize(vim.fs.abspath(vim.fs.normalize(path)))
end

---@param path string
---@return string?
local function realpath(path)
  local real = vim.uv.fs_realpath(path)
  return real and vim.fs.normalize(real) or nil
end

---Store `value` under the normalised path and, when it differs, under its realpath.
local function put(map, path, value)
  local norm = normalize(path)
  map[norm] = value
  local real = realpath(norm)
  if real and real ~= norm then
    map[real] = value
  end
end

---Look a path up by its normalised form first, then by its realpath.
local function get(map, path)
  if not path or path == '' then
    return nil
  end
  local norm = normalize(path)
  local hit = map[norm]
  if hit then
    return hit
  end
  local real = realpath(norm)
  return real and map[real] or nil
end

---@param path string
---@return string? source
function M.source_of(path)
  return get(by_target, path)
end

---@param path string
---@return string? target
function M.target_of(path)
  return get(by_source, path)
end

---True when `path` is an indexed target or the source of one. Runs no process.
---@param path string
---@return boolean
function M.is_managed(path)
  return M.source_of(path) ~= nil or M.target_of(path) ~= nil
end

---Absolute paths of all indexed targets, including realpath variants.
---@return string[]
function M.targets()
  return vim.tbl_keys(by_target)
end

---True when `path` is inside the source directory.
---@param path string
---@return boolean
function M.in_source_dir(path)
  if not M.source_dir or not path or path == '' then
    return false
  end
  local dir = M.source_dir .. '/'
  local norm = normalize(path)
  if norm:sub(1, #dir) == dir then
    return true
  end
  local real = realpath(norm) or realpath(vim.fs.dirname(norm))
  return real ~= nil and (real .. '/'):sub(1, #dir) == dir
end

---Register a function called after every build, on success and on failure.
---@param fn fun(became_ready: boolean)
function M.on_change(fn)
  listeners[#listeners + 1] = fn
end

local function warn_once(msg)
  if warned ~= msg then
    warned = msg
    vim.notify('chezmoi: ' .. msg .. '; plugin inactive', vim.log.levels.WARN)
  end
end

---@param err string?
---@param source_dir string?
---@param t2s table<string, string>?
---@param s2t table<string, string>?
---@param count integer?
---@param quiet boolean
local function finish(err, source_dir, t2s, s2t, count, quiet)
  local was_ready = M.ready
  if err then
    M.ready, M.source_dir, M.error, M.count = false, nil, err, 0
    by_target, by_source = {}, {}
    if not quiet then
      warn_once(err)
    end
  else
    M.ready, M.source_dir, M.error, M.count = true, source_dir, nil, count or 0
    by_target, by_source = t2s or {}, s2t or {}
    warned = nil
  end

  for _, fn in ipairs(listeners) do
    fn(M.ready and not was_ready)
  end

  if dirty then
    dirty = false
    M.build(nil, { quiet = quiet })
    return
  end
  local pending = waiters
  waiters = {}
  for _, fn in ipairs(pending) do
    fn(err == nil, err)
  end
end

local function parse(sp, mg)
  if not sp.ok then
    return sp.stderr ~= '' and sp.stderr or ('chezmoi source-path exited with ' .. sp.code)
  end
  if not mg.ok then
    return mg.stderr ~= '' and mg.stderr or ('chezmoi managed exited with ' .. mg.code)
  end
  local dir = vim.trim(sp.stdout)
  local source_dir = realpath(dir)
  if not source_dir then
    return 'source directory does not exist: ' .. dir
  end

  local entries = {}
  if vim.trim(mg.stdout) ~= '' then
    local ok, decoded = pcall(vim.json.decode, mg.stdout)
    if not ok or type(decoded) ~= 'table' then
      return 'cannot parse the output of chezmoi managed'
    end
    entries = decoded
  end

  local t2s, s2t, count = {}, {}, 0
  for _, entry in pairs(entries) do
    if type(entry) == 'table' and entry.absolute and entry.sourceAbsolute then
      put(t2s, entry.absolute, normalize(entry.sourceAbsolute))
      put(s2t, entry.sourceAbsolute, normalize(entry.absolute))
      count = count + 1
    end
  end
  return nil, source_dir, t2s, s2t, count
end

---Rebuild the index asynchronously. A call while a build is running schedules one more build
---after it instead of running in parallel. `cb` runs after the build that reflects this call.
---@param cb? fun(ok: boolean, err?: string)
---@param opts? { quiet?: boolean } quiet: do not warn on failure (the caller reports it)
function M.build(cb, opts)
  opts = opts or {}
  if cb then
    waiters[#waiters + 1] = cb
  end
  if building then
    dirty = true
    return
  end
  building = true

  local function done(...)
    building = false
    finish(...)
  end

  if not runner.executable() then
    vim.schedule(function()
      done(
        'chezmoi executable not found: ' .. config.options.cmd,
        nil,
        nil,
        nil,
        nil,
        opts.quiet == true
      )
    end)
    return
  end

  local sp, mg
  local function collect()
    if sp and mg then
      local err, source_dir, t2s, s2t, count = parse(sp, mg)
      done(err, source_dir, t2s, s2t, count, opts.quiet == true)
    end
  end
  runner.run({ 'source-path' }, function(res)
    sp = res
    collect()
  end)
  runner.run({
    'managed',
    '--include=files',
    '--exclude=encrypted',
    '--path-style=all',
    '--format=json',
  }, function(res)
    mg = res
    collect()
  end)
end

---Call `cb` once the index is ready, building it if no build is running.
---@param cb fun(ok: boolean, err?: string)
function M.wait(cb)
  if building then
    waiters[#waiters + 1] = cb
  elseif M.ready then
    cb(true)
  else
    M.build(cb)
  end
end

return M
