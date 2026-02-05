--- Component builder for status view.
--- Transforms GroupedStatus data into a component tree with line mapping.
--- @module neosapling.status.components

local ui = require("neosapling.lib.ui")

local M = {}

--- Build a status section with files
---@param title string Section title (e.g., "Untracked files")
---@param files FileStatus[] Files in this section
---@param status_char string Status indicator character (e.g., "?", "M", "A")
---@param hl_group string Highlight group for status indicator
---@param section_id string Section identifier for line mapping
---@param line_map table<number, Item> Line map to populate
---@param current_line number Current line number (1-indexed)
---@return Component|nil, number Section component (nil if empty) and updated line number
local function build_section(title, files, status_char, hl_group, section_id, line_map, current_line)
  if #files == 0 then
    return nil, current_line
  end

  local section_start = current_line
  line_map[section_start] = { type = "section", id = section_id }

  local file_rows = {}
  for _, file in ipairs(files) do
    current_line = current_line + 1
    table.insert(file_rows, ui.row({
      ui.text("  " .. status_char .. " ", { hl = hl_group }),
      ui.text(file.path),
    }))
    line_map[current_line] = { type = "file", file = file, section = section_id }
  end

  local section = ui.fold(
    ui.row({
      ui.text(title, { hl = "NeoSaplingSection" }),
      ui.text(" (" .. #files .. ")"),
    }),
    file_rows,
    { id = section_id }
  )

  return section, current_line
end

--- Build status view component tree
---@param data {status: GroupedStatus}
---@return Component, table<number, Item> tree and line mapping
function M.build(data)
  local line_map = {}
  local current_line = 1

  local children = {}

  -- Header
  table.insert(children, ui.row({
    ui.text("NeoSapling Status", { hl = "NeoSaplingHeader" }),
  }))
  current_line = current_line + 1

  -- Empty line after header
  table.insert(children, ui.text(""))
  current_line = current_line + 1

  -- Untracked files section (unknown status = ?)
  local untracked, line_after_untracked = build_section(
    "Untracked files",
    data.status.unknown,
    "?",
    "NeoSaplingUntracked",
    "untracked",
    line_map,
    current_line
  )
  if untracked then
    table.insert(children, untracked)
    current_line = line_after_untracked
    -- Add empty line between sections (accounts for col's new_line before it)
    table.insert(children, ui.text(""))
    current_line = current_line + 1  -- For the empty text itself
    current_line = current_line + 1  -- For col's new_line before next section
  end

  -- Unstaged changes section (modified status = M)
  local unstaged, line_after_unstaged = build_section(
    "Unstaged changes",
    data.status.modified,
    "M",
    "NeoSaplingUnstaged",
    "unstaged",
    line_map,
    current_line
  )
  if unstaged then
    table.insert(children, unstaged)
    current_line = line_after_unstaged
    table.insert(children, ui.text(""))
    current_line = current_line + 1
    current_line = current_line + 1
  end

  -- Staged changes section (added status = A)
  local staged, line_after_staged = build_section(
    "Staged changes",
    data.status.added,
    "A",
    "NeoSaplingStaged",
    "staged",
    line_map,
    current_line
  )
  if staged then
    table.insert(children, staged)
    current_line = line_after_staged
    table.insert(children, ui.text(""))
    current_line = current_line + 1
  end

  return ui.col(children), line_map
end

return M
