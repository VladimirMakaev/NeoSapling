-- lua/neosapling/lib/cli/init.lua
-- CLI module entry point - exports convenient methods for Sapling CLI operations

local runner = require("neosapling.lib.cli.runner")
local CommandBuilder = require("neosapling.lib.cli.builder")

local M = {}

-- =============================================================================
-- Factory methods that return pre-configured builders
-- =============================================================================

--- Create a status command builder
--- Usage: sl.status():print0():call({}, callback)
---@return CommandBuilder Pre-configured builder with "status" subcommand
function M.status()
  return CommandBuilder:new(runner):status()
end

--- Create a diff command builder
--- Usage: sl.diff():git_format():rev("."):call({}, callback)
---@return CommandBuilder Pre-configured builder with "diff" subcommand
function M.diff()
  return CommandBuilder:new(runner):diff()
end

--- Create a log command builder
--- Usage: sl.log():template("{node}\\n"):call({}, callback)
---@return CommandBuilder Pre-configured builder with "log" subcommand
function M.log()
  return CommandBuilder:new(runner):log()
end

--- Create a smartlog command builder
--- Usage: sl.smartlog():template(...):call({}, callback)
---@return CommandBuilder Pre-configured builder with "smartlog" subcommand
function M.smartlog()
  return CommandBuilder:new(runner):smartlog()
end

--- Create a commit command builder
--- Usage: sl.commit():message("msg"):call({}, callback)
---@return CommandBuilder Pre-configured builder with "commit" subcommand
function M.commit()
  return CommandBuilder:new(runner):commit()
end

--- Create an add command builder
--- Usage: sl.add():file("path/to/file"):call({}, callback)
---@return CommandBuilder Pre-configured builder with "add" subcommand
function M.add()
  return CommandBuilder:new(runner):add()
end

--- Create a forget command builder
--- Usage: sl.forget():file("path/to/file"):call({}, callback)
---@return CommandBuilder Pre-configured builder with "forget" subcommand
function M.forget()
  return CommandBuilder:new(runner):forget()
end

--- Create a revert command builder
--- Usage: sl.revert():opt("--no-backup"):file("path/to/file"):call({}, callback)
---@return CommandBuilder Pre-configured builder with "revert" subcommand
function M.revert()
  return CommandBuilder:new(runner):revert()
end

--- Create a goto command builder
--- Usage: sl.goto_rev():rev("abc123"):call({}, callback)
---@return CommandBuilder Pre-configured builder with "goto" subcommand
function M.goto_rev()
  return CommandBuilder:new(runner):goto_rev()
end

--- Create an amend command builder
--- Usage: sl.amend():no_edit():call({}, callback)
---@return CommandBuilder Pre-configured builder with "amend" subcommand
function M.amend()
  return CommandBuilder:new(runner):amend()
end

--- Create an absorb command builder
--- Usage: sl.absorb():call({}, callback)
---@return CommandBuilder Pre-configured builder with "absorb" subcommand
function M.absorb()
  return CommandBuilder:new(runner):absorb()
end

--- Create a rebase command builder
--- Usage: sl.rebase():dest("main"):call({}, callback)
---@return CommandBuilder Pre-configured builder with "rebase" subcommand
function M.rebase()
  return CommandBuilder:new(runner):rebase()
end

--- Create a hide command builder
--- Usage: sl.hide():rev("abc123"):call({}, callback)
---@return CommandBuilder Pre-configured builder with "hide" subcommand
function M.hide()
  return CommandBuilder:new(runner):hide()
end

--- Create an unhide command builder
--- Usage: sl.unhide():rev("abc123"):call({}, callback)
---@return CommandBuilder Pre-configured builder with "unhide" subcommand
function M.unhide()
  return CommandBuilder:new(runner):unhide()
end

--- Create a pull command builder
--- Usage: sl.pull():call({}, callback)
---@return CommandBuilder Pre-configured builder with "pull" subcommand
function M.pull()
  return CommandBuilder:new(runner):pull()
end

--- Create an uncommit command builder
--- Usage: sl.uncommit():call({}, callback)
---@return CommandBuilder Pre-configured builder with "uncommit" subcommand
function M.uncommit()
  return CommandBuilder:new(runner):uncommit()
end

--- Create an unamend command builder
--- Usage: sl.unamend():call({}, callback)
---@return CommandBuilder Pre-configured builder with "unamend" subcommand
function M.unamend()
  return CommandBuilder:new(runner):unamend()
end

--- Create a graft command builder
--- Usage: sl.graft():rev("abc123"):call({}, callback)
---@return CommandBuilder Pre-configured builder with "graft" subcommand
function M.graft()
  return CommandBuilder:new(runner):graft()
end

--- Create a bookmark command builder
--- Usage: sl.bookmarks():template(...):call({}, callback)
---@return CommandBuilder Pre-configured builder with "bookmark" subcommand
function M.bookmarks()
  return CommandBuilder:new(runner):bookmark()
end

--- Create a metaedit command builder
--- Usage: sl.metaedit():rev("abc123"):opt("-l", tmpfile):call({}, callback)
---@return CommandBuilder Pre-configured builder with "metaedit" subcommand
function M.metaedit()
  return CommandBuilder:new(runner):metaedit()
end

-- =============================================================================
-- Low-level access for advanced usage
-- =============================================================================

--- Raw run method for arbitrary commands
--- Usage: sl.run({"sl", "custom", "command"}, {}, callback)
M.run = runner.run

--- Builder class for creating custom command builders
--- Usage: local b = sl.Builder:new(runner)
M.Builder = CommandBuilder

--- Create a new empty builder for custom commands
--- Usage: sl.builder():arg("custom"):call({}, callback)
---@return CommandBuilder Fresh builder starting with "sl"
function M.builder()
  return CommandBuilder:new(runner)
end

return M
