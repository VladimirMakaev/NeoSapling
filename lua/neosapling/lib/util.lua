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

--- Find the root directory of a Sapling/Mercurial repository
---
--- Uses `sl root` or `hg root` for reliable detection.
--- Works with both .sl and .hg repositories.
---
---@param path? string Starting path (defaults to vim.fn.getcwd())
---@return string|nil Root directory path if found, nil otherwise
function M.find_root(path)
  path = path or vim.fn.getcwd()

  -- Use sl root (Sapling handles both .sl and .hg repos)
  if vim.fn.executable("sl") == 1 then
    local result = vim.system({ "sl", "root" }, { text = true, cwd = path, timeout = 5000 }):wait()
    if result.code == 0 and result.stdout then
      local root = vim.trim(type(result.stdout) == "table" and table.concat(result.stdout, "") or result.stdout)
      if root ~= "" then return root end
    end
  end

  -- Fallback: search for .sl or .hg directory
  local dirs = vim.fs.find({ ".sl", ".hg" }, {
    upward = true,
    path = path,
    type = "directory",
  })
  if #dirs > 0 then
    return vim.fn.fnamemodify(dirs[1], ":h")
  end

  return nil
end

return M
