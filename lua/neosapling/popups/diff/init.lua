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

--- Show unified diff in a split buffer (built-in fallback)
---@param commit SslCommit|CommitExtended
---@param diff_opts table Options for sl.diff ({change=node} or {rev=node})
---@param diff_type string Description ("vs parent" or "vs working copy")
local function show_unified_diff(commit, diff_opts, diff_type)
  local neosapling = require("neosapling")
  local smartlog = require("neosapling.smartlog")

  vim.notify("Loading diff " .. diff_type .. "...", vim.log.levels.INFO)

  neosapling.sl.diff(diff_opts, function(diffs, err)
    if err then
      vim.notify("Diff failed: " .. err, vim.log.levels.ERROR)
      return
    end

    vim.schedule(function()
      smartlog._show_diff_buffer(diffs, commit, diff_type)
    end)
  end)
end

--- Diff commit against its parent (show changes introduced by this commit)
---@param commit SslCommit|CommitExtended
function M._diff_vs_parent(commit)
  -- Try diffview.nvim first — fall through to unified diff if it fails
  local split = require("neosapling.diff.split")
  if split.has_diffview() then
    local ok = split.open_commit_diff(commit.node, "parent")
    if ok ~= false then return end
    -- diffview failed (returned false), fall through to unified diff
  end

  -- Built-in: unified diff in split buffer
  -- sl diff -c {node} shows changes introduced by the commit (diff against parent)
  show_unified_diff(commit, { change = commit.node }, "vs parent")
end

--- Diff commit against working copy (show what changed since this commit)
---@param commit SslCommit|CommitExtended
function M._diff_vs_working(commit)
  -- Try diffview.nvim first — fall through to unified diff if it fails
  local split = require("neosapling.diff.split")
  if split.has_diffview() then
    local ok = split.open_commit_diff(commit.node, "working")
    if ok ~= false then return end
    -- diffview failed (returned false), fall through to unified diff
  end

  -- Built-in: unified diff in split buffer
  -- sl diff -r {node} shows working copy changes relative to that commit
  show_unified_diff(commit, { rev = commit.node }, "vs working copy")
end

return M
