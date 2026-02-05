--- PopupBuilder: Fluent API for declarative popup definitions.
--- @module neosapling.popups.builder

local M = {}

---@class PopupState
---@field name string Popup name
---@field groups PopupGroup[] Action groups
---@field current_group PopupGroup|nil Current group being built

---@class PopupGroup
---@field heading string|nil Group heading
---@field actions PopupAction[]

---@class PopupAction
---@field keys string[] Keys that trigger this action
---@field description string Human-readable description
---@field callback function Action function

---@class PopupDefinition
---@field name string Popup name
---@field groups PopupGroup[] Action groups

---@class PopupBuilder
local PopupBuilder = {}
PopupBuilder.__index = PopupBuilder

--- Create new popup builder
---@return PopupBuilder
function M.builder()
  local self = setmetatable({}, PopupBuilder)
  self.state = {
    name = nil,
    groups = {},
    current_group = nil,
  }
  return self
end

--- Set popup name
---@param name string
---@return PopupBuilder
function PopupBuilder:name(name)
  self.state.name = name
  return self
end

--- Start a new action group
---@param heading string|nil Optional heading
---@return PopupBuilder
function PopupBuilder:group(heading)
  if self.state.current_group then
    table.insert(self.state.groups, self.state.current_group)
  end
  self.state.current_group = {
    heading = heading,
    actions = {},
  }
  return self
end

--- Add an action to current group
---@param keys string|string[] Key(s) that trigger action
---@param description string Human-readable description
---@param callback function Action function
---@return PopupBuilder
function PopupBuilder:action(keys, description, callback)
  if not self.state.current_group then
    self:group(nil)
  end
  local key_list = type(keys) == "table" and keys or { keys }
  table.insert(self.state.current_group.actions, {
    keys = key_list,
    description = description,
    callback = callback,
  })
  return self
end

--- Build and return the popup definition
---@return PopupDefinition
function PopupBuilder:build()
  if self.state.current_group then
    table.insert(self.state.groups, self.state.current_group)
  end

  assert(self.state.name, "Popup must have a name")

  return {
    name = self.state.name,
    groups = self.state.groups,
  }
end

return M
