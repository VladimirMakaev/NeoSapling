-- NeoSapling: Sapling VCS integration for Neovim
-- Main plugin entry point

local cli = require("neosapling.lib.cli")
local parsers = require("neosapling.lib.parsers")
local util = require("neosapling.lib.util")

local M = {}

-- Plugin configuration (set by setup())
M.config = {}

--- Initialize NeoSapling plugin
---
--- Call this from your init.lua to configure the plugin.
--- Validates that Sapling (sl) is available before initializing.
---
---@param opts? table Optional configuration table
---@return boolean true if setup succeeded, false if sl not found
function M.setup(opts)
  -- Configure plugin
  local config = require("neosapling.lib.config")
  config.setup(opts)
  M.config = config.values

  -- Validate sl is available
  if not util.check_sapling() then
    return false
  end

  -- Setup highlights
  require("neosapling.lib.ui.highlights").setup()

  -- Early Watchman detection (caches availability for later use)
  require("neosapling.lib.watcher").is_available()

  -- Register user commands
  vim.api.nvim_create_user_command("NeoSapling", function()
    require("neosapling.status").open()
  end, { desc = "Open NeoSapling status view" })

  vim.api.nvim_create_user_command("NeoSaplingLog", function()
    require("neosapling.smartlog").open()
  end, { desc = "Open NeoSapling smartlog view" })

  return true
end

-- =============================================================================
-- High-level async operations with parsing (M.sl namespace)
-- =============================================================================

M.sl = {}

--- Get repository status asynchronously
---
--- Runs `sl status --print0` and parses the output into grouped file statuses.
---
---@param callback fun(status: GroupedStatus|nil, err: string|nil)
---@return vim.SystemObj|nil Handle for cancellation, nil if sl not found
function M.sl.status(callback)
  cli.status():print0():call({}, function(result)
    if result.code ~= 0 then
      callback(nil, "sl status failed: " .. table.concat(result.stderr, "\n"))
      return
    end

    local files = parsers.status.parse(result.stdout)
    local grouped = parsers.status.group(files)
    callback(grouped, nil)
  end)
end

--- Get diff asynchronously
---
--- Runs `sl diff --git` and parses the output into structured file diffs.
---
---@param opts? {rev?: string, files?: string[]} Optional revision and file filters
---@param callback fun(diffs: FileDiff[]|nil, err: string|nil)
---@return vim.SystemObj|nil Handle for cancellation
function M.sl.diff(opts, callback)
  opts = opts or {}

  local builder = cli.diff():git_format()

  -- Add revision if specified
  if opts.rev then
    builder:rev(opts.rev)
  end

  -- Add file filters if specified
  if opts.files and #opts.files > 0 then
    builder:files(opts.files)
  end

  builder:call({}, function(result)
    if result.code ~= 0 then
      callback(nil, "sl diff failed: " .. table.concat(result.stderr, "\n"))
      return
    end

    local diffs = parsers.diff.parse(result.stdout)
    callback(diffs, nil)
  end)
end

--- Get smartlog asynchronously
---
--- Runs `sl smartlog -T TEMPLATE` and parses the output into commit objects.
---
---@param callback fun(commits: Commit[]|nil, err: string|nil)
---@return vim.SystemObj|nil Handle for cancellation
function M.sl.smartlog(callback)
  cli.smartlog():template(parsers.smartlog.TEMPLATE):call({}, function(result)
    if result.code ~= 0 then
      callback(nil, "sl smartlog failed: " .. table.concat(result.stderr, "\n"))
      return
    end

    local commits = parsers.smartlog.parse(result.stdout)
    callback(commits, nil)
  end)
end

--- Get extended smartlog with parent data asynchronously
---
--- Runs `sl smartlog -T TEMPLATE_EXTENDED` and parses output with parent node data.
--- Extended commits include p1node and p2node fields for parent relationships.
---
---@param callback fun(commits: CommitExtended[]|nil, err: string|nil)
---@return vim.SystemObj|nil Handle for cancellation
function M.sl.smartlog_extended(callback)
  cli.smartlog():template(parsers.smartlog.TEMPLATE_EXTENDED):call({}, function(result)
    if result.code ~= 0 then
      callback(nil, "sl smartlog failed: " .. table.concat(result.stderr, "\n"))
      return
    end

    local commits = parsers.smartlog.parse_extended(result.stdout)
    callback(commits, nil)
  end)
end

--- Get bookmarks asynchronously
---
--- Runs `sl bookmark -T TEMPLATE` and parses the output into bookmark objects.
---
---@param callback fun(bookmarks: Bookmark[]|nil, err: string|nil)
---@return vim.SystemObj|nil Handle for cancellation
function M.sl.bookmarks(callback)
  cli.bookmarks():template(parsers.bookmarks.TEMPLATE):call({}, function(result)
    if result.code ~= 0 then
      callback(nil, "sl bookmark failed: " .. table.concat(result.stderr, "\n"))
      return
    end

    local bookmarks = parsers.bookmarks.parse(result.stdout)
    callback(bookmarks, nil)
  end)
end

-- =============================================================================
-- Raw CLI access for advanced usage
-- =============================================================================

--- Raw CLI module access
--- Usage: require("neosapling").sl.raw.status():print0():call({}, callback)
M.sl.raw = cli

return M
