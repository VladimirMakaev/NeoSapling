--- Context tracking for status buffer.
--- Maps line numbers to data items for cursor-aware actions.
--- @module neosapling.status.context

local M = {}

---@alias ItemType "section"|"file"|"hunk"|"commit"|"bookmark"
---@alias Item {type: ItemType, [string]: any}

--- Get the item at the current cursor line
---@param line_map table<number, Item>
---@return Item|nil
function M.get_item_at_cursor(line_map)
  local line = vim.fn.line(".")
  return line_map[line]
end

--- Get the item at a specific line
---@param line_map table<number, Item>
---@param lnum number Line number (1-indexed)
---@return Item|nil
function M.get_item_at_line(line_map, lnum)
  return line_map[lnum]
end

return M
