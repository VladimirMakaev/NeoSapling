--- Diff popup for smartlog commits.
--- Allows selection of diff type: vs parent or vs working copy.
--- @module neosapling.popups.diff

local popup = require("neosapling.popups.builder")
local popups = require("neosapling.popups")

local M = {}

--- Create and show the diff popup for a commit
---@param commit SslCommit|CommitExtended The commit to diff
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
---@param commit SslCommit|CommitExtended
function M._diff_vs_parent(commit)
  -- Try diffview.nvim first
  local split = require("neosapling.diff.split")
  if split.has_diffview() then
    split.open_commit_diff(commit.node, "parent")
    return
  end

  -- Fallback: unified diff in split buffer
  local neosapling = require("neosapling")
  local smartlog = require("neosapling.smartlog")

  vim.notify("Loading diff vs parent...", vim.log.levels.INFO)

  -- sl diff -r {node} shows changes introduced by the commit (diff against parent)
  -- This works for all commits including root commits
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
---@param commit SslCommit|CommitExtended
function M._diff_vs_working(commit)
  -- Try diffview.nvim first
  local split = require("neosapling.diff.split")
  if split.has_diffview() then
    split.open_commit_diff(commit.node, "working")
    return
  end

  -- Fallback: unified diff in split buffer
  local neosapling = require("neosapling")
  local smartlog = require("neosapling.smartlog")

  vim.notify("Loading diff vs working copy...", vim.log.levels.INFO)

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
