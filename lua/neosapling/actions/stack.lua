--- Stack action handlers for NeoSapling.
--- Implements goto, amend, absorb, uncommit, unamend, hide, unhide, pull, rebase, and graft.
--- @module neosapling.actions.stack

local cli = require("neosapling.lib.cli")

local M = {}

--- Schedule refresh of both status and smartlog views (dual-view refresh pattern).
--- Uses pcall to safely handle cases where either module isn't loaded.
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

--- Navigate to a specific commit revision.
--- Reloads stale buffers via checktime after successful goto.
---@param node string Revision identifier to navigate to
function M.goto_commit(node)
  cli.goto_rev():rev(node):call({}, function(result)
    if result.code == 0 then
      schedule_refresh()
      vim.cmd("checktime")
      vim.notify("Moved to " .. node, vim.log.levels.INFO)
    else
      local stderr = table.concat(result.stderr, "\n")
      if stderr:match("uncommitted changes") or stderr:match("pending changes") then
        vim.notify("Cannot goto: uncommitted changes present", vim.log.levels.WARN)
      else
        vim.notify("Goto failed: " .. stderr, vim.log.levels.ERROR)
      end
    end
  end)
end

--- Amend the current commit without opening an editor.
function M.amend_no_edit()
  cli.amend():no_edit():call({}, function(result)
    if result.code == 0 then
      schedule_refresh()
      vim.notify("Amended commit", vim.log.levels.INFO)
    else
      local stderr = table.concat(result.stderr, "\n")
      vim.notify("Amend failed: " .. stderr, vim.log.levels.ERROR)
    end
  end)
end

--- Amend the current commit interactively using buffer-based editor.
--- Opens editor pre-filled with current commit message.
function M.amend_interactive()
  require("neosapling.commit.editor").open({ amend = true })
end

--- Preview absorb changes (dry-run mode).
--- NEVER calls bare absorb -- uses --dry-run to avoid curses UI.
---@param callback fun(lines: string[]) Called with preview output lines
function M.absorb_preview(callback)
  cli.absorb():opt("--dry-run"):call({}, function(result)
    if result.code == 0 then
      callback(result.stdout)
    else
      local stderr = table.concat(result.stderr, "\n")
      vim.notify("Absorb preview failed: " .. stderr, vim.log.levels.ERROR)
    end
  end)
end

--- Apply absorb (auto-fold changes into appropriate commits).
--- Uses -a flag to apply without interactive curses UI.
function M.absorb_apply()
  cli.absorb():opt("-a"):call({}, function(result)
    if result.code == 0 then
      schedule_refresh()
      vim.notify("Absorb applied", vim.log.levels.INFO)
    else
      local stderr = table.concat(result.stderr, "\n")
      vim.notify("Absorb failed: " .. stderr, vim.log.levels.ERROR)
    end
  end)
end

--- Preview absorb and prompt user to apply.
--- Shows dry-run output, then confirms before applying.
function M.absorb_with_preview()
  M.absorb_preview(function(lines)
    -- Filter empty lines
    local content = {}
    for _, line in ipairs(lines) do
      if line ~= "" then
        table.insert(content, line)
      end
    end

    if #content == 0 then
      vim.notify("Nothing to absorb", vim.log.levels.INFO)
      return
    end

    vim.notify("Absorb preview:\n" .. table.concat(content, "\n"), vim.log.levels.INFO)

    local choice = vim.fn.confirm("Apply absorb?", "&Yes\n&No", 2)
    if choice == 1 then
      M.absorb_apply()
    end
  end)
end

--- Uncommit the current commit (move changes back to working copy).
function M.uncommit()
  cli.uncommit():call({}, function(result)
    if result.code == 0 then
      schedule_refresh()
      vim.notify("Uncommitted changes", vim.log.levels.INFO)
    else
      local stderr = table.concat(result.stderr, "\n")
      vim.notify("Uncommit failed: " .. stderr, vim.log.levels.ERROR)
    end
  end)
end

--- Unamend the current commit (restore previously amended changes).
function M.unamend()
  cli.unamend():call({}, function(result)
    if result.code == 0 then
      schedule_refresh()
      vim.notify("Unamended changes", vim.log.levels.INFO)
    else
      local stderr = table.concat(result.stderr, "\n")
      vim.notify("Unamend failed: " .. stderr, vim.log.levels.ERROR)
    end
  end)
end

--- Hide a commit (mark as obsolete).
---@param node string Revision identifier to hide
function M.hide(node)
  cli.hide():rev(node):call({}, function(result)
    if result.code == 0 then
      schedule_refresh()
      vim.notify("Hidden " .. node, vim.log.levels.INFO)
    else
      local stderr = table.concat(result.stderr, "\n")
      vim.notify("Hide failed: " .. stderr, vim.log.levels.ERROR)
    end
  end)
end

--- Unhide a previously hidden commit.
---@param node string Revision identifier to unhide
function M.unhide(node)
  cli.unhide():rev(node):call({}, function(result)
    if result.code == 0 then
      schedule_refresh()
      vim.notify("Unhidden " .. node, vim.log.levels.INFO)
    else
      local stderr = table.concat(result.stderr, "\n")
      vim.notify("Unhide failed: " .. stderr, vim.log.levels.ERROR)
    end
  end)
end

--- Pull from remote repository.
--- Shows a notification before starting since this is a long-running operation.
function M.pull()
  vim.notify("Pulling from remote...", vim.log.levels.INFO)
  cli.pull():call({}, function(result)
    if result.code == 0 then
      schedule_refresh()
      vim.notify("Pull complete", vim.log.levels.INFO)
    else
      local stderr = table.concat(result.stderr, "\n")
      vim.notify("Pull failed: " .. stderr, vim.log.levels.ERROR)
    end
  end)
end

--- Rebase onto a destination revision.
--- Uses terminal command for conflict handling output.
---@param dest string Destination revision to rebase onto
function M.rebase(dest)
  vim.cmd("!sl rebase -d " .. vim.fn.shellescape(dest))
  schedule_refresh()
end

--- Graft (cherry-pick) a commit into the current stack.
---@param node string Revision identifier to graft
function M.graft(node)
  cli.graft():rev(node):call({}, function(result)
    if result.code == 0 then
      schedule_refresh()
      vim.notify("Grafted " .. node, vim.log.levels.INFO)
    else
      local stderr = table.concat(result.stderr, "\n")
      vim.notify("Graft failed: " .. stderr, vim.log.levels.ERROR)
    end
  end)
end

return M
