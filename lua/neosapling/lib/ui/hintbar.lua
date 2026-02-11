--- Shared hint bar builder for NeoSapling views.
--- Builds one or more hint bar lines showing key bindings with distinct highlighting.
--- @module neosapling.lib.ui.hintbar

local M = {}

--- Build a single hint bar line and its highlights
---@param hints {key: string, action: string}[] Array of {key, action} pairs
---@param line_offset number 0-indexed line number where this line will appear
---@return string line The rendered hint bar text
---@return table[] highlights Array of {line, col_start, col_end, hl} highlight entries
local function build_line(hints, line_offset)
  local parts = {}
  local highlights = {}
  local byte_pos = 0

  for i, hint in ipairs(hints) do
    -- Key
    local key = hint.key
    table.insert(highlights, {
      line = line_offset,
      col_start = byte_pos,
      col_end = byte_pos + #key,
      hl = "NeoSaplingHintKey",
    })
    byte_pos = byte_pos + #key

    -- Space between key and action
    byte_pos = byte_pos + 1

    -- Action
    local action = hint.action
    table.insert(highlights, {
      line = line_offset,
      col_start = byte_pos,
      col_end = byte_pos + #action,
      hl = "NeoSaplingHintAction",
    })
    byte_pos = byte_pos + #action

    -- Build the text part: "key action"
    local part = key .. " " .. action

    -- Two spaces separator between pairs (except after last)
    if i < #hints then
      part = part .. "  "
      byte_pos = byte_pos + 2
    end

    table.insert(parts, part)
  end

  return table.concat(parts), highlights
end

--- Build hint bar lines and highlights from rows of hints
---@param rows {key: string, action: string}[][] Array of rows, each row is an array of {key, action} pairs
---@param line_offset number 0-indexed line number where the first row will appear
---@return string[] lines Array of rendered hint bar lines
---@return table[] highlights Array of {line, col_start, col_end, hl} highlight entries
function M.build(rows, line_offset)
  local lines = {}
  local highlights = {}

  for i, row in ipairs(rows) do
    local line, hls = build_line(row, line_offset + (i - 1))
    table.insert(lines, line)
    for _, hl in ipairs(hls) do
      table.insert(highlights, hl)
    end
  end

  return lines, highlights
end

return M
