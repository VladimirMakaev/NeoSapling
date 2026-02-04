-- lua/neosapling/lib/cli/runner.lua
-- Async process execution with partial line handling for Sapling CLI

local M = {}

---@class ProcessResult
---@field code number Exit code
---@field stdout string[] Lines of stdout
---@field stderr string[] Lines of stderr
---@field signal number|nil Signal if killed

---@class ProcessOpts
---@field cwd? string Working directory
---@field timeout? number Timeout in milliseconds
---@field on_stdout? fun(data: string) Streaming stdout callback
---@field on_stderr? fun(data: string) Streaming stderr callback

--- Accumulate partial line data into buffer
--- Data arrives in arbitrary chunks due to OS buffering.
--- First element continues previous incomplete line, rest are new lines.
---@param acc string[] Accumulator buffer (initialized as {""})
---@param data string[] Incoming data split by newlines
local function accumulate(acc, data)
  -- First element continues the previous incomplete line
  acc[#acc] = acc[#acc] .. data[1]
  -- Remaining elements are complete lines (or the start of a new partial line)
  for i = 2, #data do
    table.insert(acc, data[i])
  end
end

--- Execute command asynchronously and return result via callback
--- Uses vim.system() for non-blocking process execution.
---
---@param cmd string[] Command and arguments
---@param opts ProcessOpts? Options
---@param on_exit fun(result: ProcessResult) Callback with result
---@return vim.SystemObj Handle for cancellation
function M.run(cmd, opts, on_exit)
  opts = opts or {}

  -- Accumulators for partial line handling
  -- Initialize with empty string so first data continues nothing
  local stdout_acc = { "" }
  local stderr_acc = { "" }

  local obj = vim.system(cmd, {
    cwd = opts.cwd,
    text = true, -- Text mode for line-based output
    stdout = function(err, data)
      if data then
        local lines = vim.split(data, "\n", { plain = true })
        accumulate(stdout_acc, lines)
        if opts.on_stdout then
          opts.on_stdout(data)
        end
      end
    end,
    stderr = function(err, data)
      if data then
        local lines = vim.split(data, "\n", { plain = true })
        accumulate(stderr_acc, lines)
        if opts.on_stderr then
          opts.on_stderr(data)
        end
      end
    end,
  }, function(result)
    -- vim.system callback runs on exit
    -- Use vim.schedule to ensure safe Neovim API access from callback context
    vim.schedule(function()
      on_exit({
        code = result.code,
        signal = result.signal,
        stdout = stdout_acc,
        stderr = stderr_acc,
      })
    end)
  end)

  -- Handle timeout - kill process if still running after timeout
  if opts.timeout then
    vim.defer_fn(function()
      if obj:is_closing() == false then
        obj:kill("SIGTERM")
      end
    end, opts.timeout)
  end

  return obj
end

return M
