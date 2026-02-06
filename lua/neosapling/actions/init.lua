--- Actions module for NeoSapling.
--- Exports file, stack, and hunk action handlers.
--- @module neosapling.actions

return {
  file = require("neosapling.actions.file"),
  stack = require("neosapling.actions.stack"),
}
