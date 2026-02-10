--- Component builder for smartlog view.
--- Transforms ssl output lines into display lines with highlights and line mapping.
--- Phase 8.1: Replaced component-tree approach with direct ssl line rendering.
--- @module neosapling.smartlog.components

local M = {}

---Build smartlog view from ssl output lines
---@param ssl_lines string[] Raw lines from sl smartlog -T '{ssl}'
---@return string[] lines Display lines for buffer
---@return table[] highlights Highlight definitions with line, col_start, col_end, hl
---@return table<number, Item> line_map Maps 1-indexed line number to { type, commit }
function M.build(ssl_lines)
  local ssl_parser = require("neosapling.lib.parsers.smartlog_ssl")
  return ssl_parser.build(ssl_lines)
end

return M
