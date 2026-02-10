--- Shared hint bar builder for NeoSapling views.
--- Builds a single-line hint bar showing key bindings with distinct highlighting.
--- @module neosapling.lib.ui.hintbar

local M = {}

--- Build hint bar line and highlights
---@param hints {key: string, action: string}[] Array of {key, action} pairs
---@param line_offset number 0-indexed line number where the hint bar will appear in the buffer
---@return string line The rendered hint bar text
---@return table[] highlights Array of {line, col_start, col_end, hl} highlight entries
function M.build(hints, line_offset)
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
    byte_pos = byte_pos + 1 -- for the space

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

return M
