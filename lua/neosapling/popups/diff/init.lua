--- Diff popup for smartlog commits.
--- Allows selection of diff type: vs parent or vs working copy.
--- @module neosapling.popups.diff

local popup = require("neosapling.popups.builder")
local popups = require("neosapling.popups")

local M = {}

--- Create and show the diff popup for a commit
---@param commit CommitExtended The commit to diff
---@return Buffer
function M.create(commit)
  local short_hash = commit.node:sub(1, 7)

  local p = popup.builder()
    :name("Diff")
    :group("Compare " .. short_hash)
      :action("p", "Diff vs parent", function()
        M._diff_vs_parent(commit)
      end)
      :action("w", "Diff vs working copy", function()
        M._diff_vs_working(commit)
      end)
    :group()
      :action("q", "Close", function() end)
      :action("<Esc>", "Close", function() end)
    :build()

  return popups.show(p)
end

--- Diff commit against its parent
---@param commit CommitExtended
function M._diff_vs_parent(commit)
  local neosapling = require("neosapling")
  local smartlog = require("neosapling.smartlog")

  -- Check if commit has a parent
  if not commit.p1node then
    vim.notify("No parent commit to diff against (this is a root commit)", vim.log.levels.WARN)
    return
  end

  -- Diff: show changes introduced by this commit
  -- Use -c flag for "changes in this commit" or -r "p1node::node"
  -- The proper rev spec for "changes in commit X" is: -r "X^::X" or just -c X
  neosapling.sl.diff({ rev = commit.node }, function(diffs, err)
    if err then
      vim.notify("Diff failed: " .. err, vim.log.levels.ERROR)
      return
    end

    vim.schedule(function()
      smartlog._show_diff_buffer(diffs, commit, "vs parent")
    end)
  end)
end

--- Diff commit against working copy
---@param commit CommitExtended
function M._diff_vs_working(commit)
  local neosapling = require("neosapling")
  local smartlog = require("neosapling.smartlog")

  -- Diff working copy against commit: what has changed since that commit
  neosapling.sl.diff({ rev = commit.node }, function(diffs, err)
    if err then
      vim.notify("Diff failed: " .. err, vim.log.levels.ERROR)
      return
    end

    vim.schedule(function()
      smartlog._show_diff_buffer(diffs, commit, "vs working copy")
    end)
  end)
end

return M
