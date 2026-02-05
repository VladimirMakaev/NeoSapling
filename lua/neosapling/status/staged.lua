--- Virtual staging for modified files.
--- Sapling has no index; this tracks which modified files to include in commit.
--- @module neosapling.status.staged

local M = {}

-- Set of staged file paths (path -> true)
local staged_files = {}

--- Stage a file (add to staged set)
---@param path string File path
function M.stage(path)
  staged_files[path] = true
end

--- Unstage a file (remove from staged set)
---@param path string File path
function M.unstage(path)
  staged_files[path] = nil
end

--- Check if file is staged
---@param path string File path
---@return boolean
function M.is_staged(path)
  return staged_files[path] == true
end

--- Get all staged file paths
---@return string[]
function M.get_staged()
  local paths = {}
  for path, _ in pairs(staged_files) do
    table.insert(paths, path)
  end
  return paths
end

--- Clear all staged files (call after successful commit)
function M.clear()
  staged_files = {}
end

return M
