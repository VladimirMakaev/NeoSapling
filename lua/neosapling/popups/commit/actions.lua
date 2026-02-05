--- Commit action implementations for NeoSapling.
--- Provides commit, amend, and extend actions.
--- @module neosapling.popups.commit.actions

local M = {}

--- Schedule status buffer refresh after commit operations
local function schedule_refresh()
  vim.schedule(function()
    local ok, status = pcall(require, "neosapling.status")
    if ok and status.refresh then
      status.refresh()
    end
  end)
end

--- Create a new commit with buffer-based editor
---@param opts table|nil Optional options
function M.commit(opts)
  opts = opts or {}
  require("neosapling.commit.editor").open({ amend = false })
end

--- Amend the current commit
--- For now, uses terminal command as amend needs existing message loading
--- TODO: Implement buffer-based amend in future phase
function M.amend()
  vim.cmd("!sl commit --amend")
  schedule_refresh()
end

--- Extend the current commit without editing message
--- Adds staged changes without opening editor
function M.extend()
  vim.cmd("!sl commit --amend --no-edit")
  schedule_refresh()
end

return M
