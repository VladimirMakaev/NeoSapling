--- Configuration module for NeoSapling.
--- Provides defaults and merges user options via setup().
--- @module neosapling.lib.config

local M = {}

--- Default configuration
local defaults = {
  -- Keybindings for status buffer
  mappings = {
    status = {
      ["?"] = "help",
      ["c"] = "commit",
      ["q"] = "close",
      ["<Tab>"] = "toggle_fold",
    },
  },
  -- Popup settings
  popup = {
    border = "rounded",
  },
  -- Signs for status buffer
  signs = {
    modified = "M",
    added = "A",
    removed = "R",
    untracked = "?",
  },
}

--- Current configuration (starts as copy of defaults)
M.values = vim.deepcopy(defaults)

--- Setup configuration by merging user options with defaults
---@param opts? table User options
function M.setup(opts)
  opts = opts or {}
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
end

--- Get a configuration value by dot-separated path
---@param key string Dot-separated path (e.g., "mappings.status")
---@return any
function M.get(key)
  local parts = vim.split(key, ".", { plain = true })
  local value = M.values
  for _, part in ipairs(parts) do
    if type(value) ~= "table" then
      return nil
    end
    value = value[part]
  end
  return value
end

return M
