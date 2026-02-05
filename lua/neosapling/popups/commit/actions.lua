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

--- Create a new commit with editor
--- Opens $EDITOR for commit message
---@param opts table|nil Optional options
function M.commit(opts)
  opts = opts or {}
  vim.cmd("!sl commit")
  schedule_refresh()
end

--- Amend the current commit with editor
--- Opens $EDITOR for editing commit message
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
