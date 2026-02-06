--- Commit action implementations for NeoSapling.
--- Provides commit, amend, extend, uncommit, unamend, and absorb actions.
--- @module neosapling.popups.commit.actions

local M = {}

--- Schedule dual-view refresh after commit operations.
--- Refreshes both status and smartlog views using pcall to safely
--- handle cases where either module isn't loaded.
local function schedule_refresh()
  vim.schedule(function()
    local ok1, status = pcall(require, "neosapling.status")
    if ok1 and status.refresh then
      status.refresh()
    end
    local ok2, smartlog = pcall(require, "neosapling.smartlog")
    if ok2 and smartlog.refresh then
      smartlog.refresh()
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

--- Uncommit the current commit (move changes back to working copy).
--- Delegates to stack action handler via lazy require.
function M.uncommit()
  require("neosapling.actions.stack").uncommit()
end

--- Unamend the current commit (restore previously amended changes).
--- Delegates to stack action handler via lazy require.
function M.unamend()
  require("neosapling.actions.stack").unamend()
end

--- Absorb changes into appropriate stack commits.
--- Shows dry-run preview before applying. Delegates to stack action handler via lazy require.
function M.absorb()
  require("neosapling.actions.stack").absorb_with_preview()
end

return M
