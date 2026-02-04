-- Shared utilities for NeoSapling
-- Provides common helper functions used across the plugin

local M = {}

--- Notify user with NeoSapling prefix
---
--- Wrapper around vim.notify that adds consistent "NeoSapling: " prefix.
---
---@param msg string Message to display
---@param level? number vim.log.levels value (default: INFO)
function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  vim.notify("NeoSapling: " .. msg, level)
end

--- Check if Sapling (sl) is available in PATH
---
--- Validates that the sl binary exists and is executable.
--- Notifies user with an error message if not found.
---
---@return boolean true if sl is executable, false otherwise
function M.check_sapling()
  if vim.fn.executable("sl") == 1 then
    return true
  end

  M.notify("Sapling (sl) not found in PATH", vim.log.levels.ERROR)
  return false
end

--- Find the root directory of a Sapling repository
---
--- Starting from the given path (or cwd if nil), searches upward
--- for a ".sl" directory indicating a Sapling repository root.
---
---@param path? string Starting path (defaults to vim.fn.getcwd())
---@return string|nil Root directory path if found, nil otherwise
function M.find_root(path)
  path = path or vim.fn.getcwd()

  local result = vim.fs.find(".sl", {
    upward = true,
    path = path,
    type = "directory",
  })

  if #result > 0 then
    -- Return parent directory of .sl
    return vim.fn.fnamemodify(result[1], ":h")
  end

  return nil
end

return M
