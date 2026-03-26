-- lua/neosapling/lib/cli/builder.lua
-- Fluent command builder for Sapling CLI commands

---@class CommandBuilder
---@field _cmd string[] Accumulated command parts
---@field _runner table Reference to runner module
local CommandBuilder = {}
CommandBuilder.__index = CommandBuilder

--- Create a new CommandBuilder instance
---@param runner table Reference to runner module
---@return CommandBuilder
function CommandBuilder:new(runner)
  return setmetatable({
    _cmd = { "sl" },
    _runner = runner,
  }, self)
end

--- Add a single argument to the command
---@param value string|number Argument value
---@return CommandBuilder self for chaining
function CommandBuilder:arg(value)
  table.insert(self._cmd, tostring(value))
  return self
end

--- Add a flag with optional value
---@param flag string Flag (e.g., "-r", "--template")
---@param value? string|number Optional value for the flag
---@return CommandBuilder self for chaining
function CommandBuilder:opt(flag, value)
  table.insert(self._cmd, flag)
  if value ~= nil then
    table.insert(self._cmd, tostring(value))
  end
  return self
end

--- Execute the command and return result via callback
---@param opts ProcessOpts? Options for process execution
---@param on_exit fun(result: ProcessResult) Callback with result
---@return vim.SystemObj Handle for cancellation
function CommandBuilder:call(opts, on_exit)
  return self._runner.run(self._cmd, opts, on_exit)
end

-- =============================================================================
-- Subcommand convenience methods
-- =============================================================================

--- Add "status" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:status()
  return self:arg("status")
end

--- Add "diff" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:diff()
  return self:arg("diff")
end

--- Add "log" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:log()
  return self:arg("log")
end

--- Add "smartlog" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:smartlog()
  return self:arg("smartlog")
end

--- Add "commit" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:commit()
  return self:arg("commit")
end

--- Add "add" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:add()
  return self:arg("add")
end

--- Add "forget" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:forget()
  return self:arg("forget")
end

--- Add "revert" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:revert()
  return self:arg("revert")
end

--- Add "goto" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:goto_rev()
  return self:arg("goto")
end

--- Add "amend" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:amend()
  return self:arg("amend")
end

--- Add "absorb" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:absorb()
  return self:arg("absorb")
end

--- Add "rebase" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:rebase()
  return self:arg("rebase")
end

--- Add "hide" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:hide()
  return self:arg("hide")
end

--- Add "unhide" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:unhide()
  return self:arg("unhide")
end

--- Add "pull" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:pull()
  return self:arg("pull")
end

--- Add "uncommit" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:uncommit()
  return self:arg("uncommit")
end

--- Add "unamend" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:unamend()
  return self:arg("unamend")
end

--- Add "graft" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:graft()
  return self:arg("graft")
end

--- Add "bookmark" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:bookmark()
  return self:arg("bookmark")
end

--- Add "metaedit" subcommand
---@return CommandBuilder self for chaining
function CommandBuilder:metaedit()
  return self:arg("metaedit")
end

-- =============================================================================
-- Flag convenience methods
-- =============================================================================

--- Add "--print0" flag (NUL-separated output)
---@return CommandBuilder self for chaining
function CommandBuilder:print0()
  return self:arg("--print0")
end

--- Add "--git" flag (git diff format)
---@return CommandBuilder self for chaining
function CommandBuilder:git_format()
  return self:arg("--git")
end

--- Add "-T" template flag
---@param tmpl string Template string
---@return CommandBuilder self for chaining
function CommandBuilder:template(tmpl)
  return self:opt("-T", tmpl)
end

--- Add "-r" revision flag
---@param revision string Revision specifier
---@return CommandBuilder self for chaining
function CommandBuilder:rev(revision)
  return self:opt("-r", revision)
end

--- Add "-c" change flag (show changes introduced by a revision)
---@param revision string Revision specifier
---@return CommandBuilder self for chaining
function CommandBuilder:change(revision)
  return self:opt("-c", revision)
end

--- Add "-m" message flag
---@param message string Commit message
---@return CommandBuilder self for chaining
function CommandBuilder:message(message)
  return self:opt("-m", message)
end

--- Add "--interactive" flag
---@return CommandBuilder self for chaining
function CommandBuilder:interactive()
  return self:arg("--interactive")
end

--- Add "--no-edit" flag
---@return CommandBuilder self for chaining
function CommandBuilder:no_edit()
  return self:arg("--no-edit")
end

--- Add "-d" destination flag
---@param dest string Destination revision
---@return CommandBuilder self for chaining
function CommandBuilder:dest(dest)
  return self:opt("-d", dest)
end

--- Add file path argument
---@param path string File path
---@return CommandBuilder self for chaining
function CommandBuilder:file(path)
  return self:arg(path)
end

--- Add multiple file path arguments
---@param paths string[] File paths
---@return CommandBuilder self for chaining
function CommandBuilder:files(paths)
  for _, path in ipairs(paths) do
    table.insert(self._cmd, path)
  end
  return self
end

return CommandBuilder
