local config = require('chezmoi.config')

local M = {}

-- Subcommands that may ask a question on a terminal; with --no-tty and stdin closed they fail
-- instead of waiting for an answer.
local may_prompt = { add = true, apply = true, forget = true }

---@class chezmoi.Result
---@field ok boolean
---@field code integer
---@field stdout string
---@field stderr string trimmed

---Run chezmoi asynchronously. `cb` is always called on the main loop, never before `run` returns.
---@param args string[]
---@param cb fun(res: chezmoi.Result)
function M.run(args, cb)
  local argv = { config.options.cmd }
  if may_prompt[args[1]] then
    argv[#argv + 1] = '--no-tty'
  end
  vim.list_extend(argv, args)

  local function finish(code, stdout, stderr)
    cb({ ok = code == 0, code = code, stdout = stdout or '', stderr = vim.trim(stderr or '') })
  end

  local ok, err = pcall(
    vim.system,
    argv,
    { text = true },
    vim.schedule_wrap(function(res)
      finish(res.code, res.stdout, res.stderr)
    end)
  )
  if not ok then
    vim.schedule(function()
      finish(-1, '', tostring(err))
    end)
  end
end

---@return boolean
function M.executable()
  return vim.fn.executable(config.options.cmd) == 1
end

return M
