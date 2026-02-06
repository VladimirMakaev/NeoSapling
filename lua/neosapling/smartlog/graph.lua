-- Graph rendering utilities for smartlog view
-- Phase 6 v1: Single-column layout (multi-column deferred to v2)

local M = {}

---Assign column positions to commits
---
---For v1, all commits are in column 0 (single column).
---This provides a foundation for future multi-column work.
---
---@param commits CommitExtended[] Ordered commits (newest first)
---@return table<string, number> commit_index Map of node -> column index
---@return number max_columns Maximum column count (always 1 for v1)
function M.assign_columns(commits)
  local commit_index = {}
  for _, commit in ipairs(commits) do
    commit_index[commit.node] = 0
  end
  return commit_index, 1
end

---Build graph prefix for a commit row
---
---For v1, returns simple indent. The graphnode character is handled
---by the components module, not here.
---
---@param commit CommitExtended Current commit
---@param columns table Unused in v1, for future compatibility
---@param commit_index table<string, number> Map of node -> column index
---@return string prefix Graph prefix string (consistent 2-space indent)
function M.build_prefix(commit, columns, commit_index)
  -- v1: Simple single-column, just return consistent indent
  -- The graphnode is displayed as part of the commit row in components.lua
  return "  "
end

return M
