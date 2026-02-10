--- Component builder for status view.
--- Transforms GroupedStatus data into a component tree with line mapping.
--- @module neosapling.status.components

local ui = require("neosapling.lib.ui")
local staged = require("neosapling.status.staged")

local M = {}

--- Build a file entry with optional inline diff preview
---@param file FileStatus The file to display
---@param diff FileDiff|nil Diff data if file is expanded
---@param status_char string Status indicator character (e.g., "?", "M", "A")
---@param hl_group string Highlight group for status indicator
---@param section_id string Section identifier
---@param line_map table<number, Item> Line map to populate
---@param current_line number Current line number (1-indexed)
---@return Component, number File component and updated line number
local function build_file_entry(file, diff, status_char, hl_group, section_id, line_map, current_line)
  -- For modified files, check if virtually staged and update indicator
  local display_char = status_char
  local display_hl = hl_group
  if file.status == "M" and staged.is_staged(file.path) then
    display_char = "M*"
    display_hl = "NeoSaplingStaged"
  end

  -- Build the file header row
  local file_row = ui.row({
    ui.text("  " .. display_char .. " ", { hl = display_hl }),
    ui.text(file.path),
  })

  -- Record file in line map
  line_map[current_line] = { type = "file", file = file, section = section_id }

  -- If no diff or no hunks, return simple row
  if not diff or not diff.hunks or #diff.hunks == 0 then
    return file_row, current_line
  end

  -- Build diff hunk children
  local hunk_children = {}
  for _, hunk in ipairs(diff.hunks) do
    -- Hunk header
    current_line = current_line + 1
    local hunk_header = ui.row({
      ui.text("    @@ ", { hl = "NeoSaplingHash" }),
      ui.text("-" .. hunk.old_start .. "," .. hunk.old_count .. " +" .. hunk.new_start .. "," .. hunk.new_count),
    })
    table.insert(hunk_children, hunk_header)
    line_map[current_line] = { type = "hunk", hunk = hunk, file = file, section = section_id }

    -- Hunk lines
    for _, line in ipairs(hunk.lines) do
      current_line = current_line + 1
      local hl = nil
      if line:sub(1, 1) == "+" then
        hl = "DiffAdd"
      elseif line:sub(1, 1) == "-" then
        hl = "DiffDelete"
      end
      table.insert(hunk_children, ui.text("      " .. line, { hl = hl }))
      line_map[current_line] = { type = "diff_line", line = line, file = file, section = section_id }
    end
  end

  -- Return fold with file row as header and hunks as children
  return ui.fold(file_row, hunk_children, { id = "file:" .. file.path }), current_line
end

--- Build a status section with files
---@param title string Section title (e.g., "Untracked files")
---@param files FileStatus[] Files in this section
---@param status_char string Status indicator character (e.g., "?", "M", "A")
---@param hl_group string Highlight group for status indicator
---@param section_id string Section identifier for line mapping
---@param line_map table<number, Item> Line map to populate
---@param current_line number Current line number (1-indexed)
---@param expanded_files table<string, FileDiff>|nil Map of expanded file paths to their diffs
---@return Component|nil, number Section component (nil if empty) and updated line number
local function build_section(title, files, status_char, hl_group, section_id, line_map, current_line, expanded_files)
  if #files == 0 then
    return nil, current_line
  end

  expanded_files = expanded_files or {}

  local section_start = current_line
  line_map[section_start] = { type = "section", id = section_id }

  local file_entries = {}
  for _, file in ipairs(files) do
    current_line = current_line + 1
    local diff = expanded_files[file.path]
    local entry, line_after_entry = build_file_entry(
      file, diff, status_char, hl_group, section_id, line_map, current_line
    )
    table.insert(file_entries, entry)
    current_line = line_after_entry
  end

  local section = ui.fold(
    ui.row({
      ui.text(title, { hl = "NeoSaplingSection" }),
      ui.text(" (" .. #files .. ")"),
    }),
    file_entries,
    { id = section_id }
  )

  return section, current_line
end

--- Build the smartlog tree section using sl-format output with highlights and commit navigation
---@param sl_lines string[] Raw lines from sl smartlog -T '{sl}'
---@param line_map table<number, Item> Line map to populate
---@param current_line number Current line number (1-indexed)
---@return Component|nil, number, table[] Smartlog section (nil if empty), updated line number, extra highlights
local function build_smartlog_section(sl_lines, line_map, current_line)
  if not sl_lines or #sl_lines == 0 then
    return nil, current_line, {}
  end

  -- Filter out trailing empty lines
  local clean_lines = {}
  for _, line in ipairs(sl_lines) do
    if line ~= "" or #clean_lines > 0 then
      table.insert(clean_lines, line)
    end
  end
  -- Remove trailing empties
  while #clean_lines > 0 and clean_lines[#clean_lines] == "" do
    table.remove(clean_lines)
  end

  if #clean_lines == 0 then
    return nil, current_line, {}
  end

  -- Parse sl output using the ssl parser (same format on OSS)
  local ssl_parser = require("neosapling.lib.parsers.smartlog_ssl")
  local _, raw_highlights, sl_line_map = ssl_parser.build(clean_lines)

  local section_start = current_line
  line_map[section_start] = { type = "section", id = "smartlog" }

  -- Build text components for each sl line, and translate line_map entries
  local tree_rows = {}
  local extra_highlights = {}
  for i, line in ipairs(clean_lines) do
    current_line = current_line + 1
    table.insert(tree_rows, ui.text(line))

    -- Transfer line map entries from ssl parser (adjusted to status buffer line numbers)
    local sl_item = sl_line_map[i]
    if sl_item then
      line_map[current_line] = sl_item
    end
  end

  -- Translate highlights from ssl parser (0-indexed lines relative to sl output)
  -- to status buffer positions (offset by section_start)
  for _, hl in ipairs(raw_highlights) do
    table.insert(extra_highlights, {
      line = hl.line + section_start, -- section_start is the header line, +1 for first content = section_start+1, but hl.line is already 0-indexed from ssl parser so line 0 = first sl line = section_start+1 in buffer = section_start in 0-indexed
      col_start = hl.col_start,
      col_end = hl.col_end,
      hl = hl.hl,
    })
  end

  local section = ui.fold(
    ui.row({
      ui.text("Smartlog", { hl = "NeoSaplingSection" }),
      ui.text(" (" .. #clean_lines .. " lines)"),
    }),
    tree_rows,
    { id = "smartlog" }
  )

  return section, current_line, extra_highlights
end

--- Build a bookmarks section
---@param bookmarks Bookmark[] Bookmarks from sl bookmark
---@param line_map table<number, Item> Line map to populate
---@param current_line number Current line number (1-indexed)
---@return Component|nil, number Bookmarks section (nil if empty) and updated line number
local function build_bookmarks_section(bookmarks, line_map, current_line)
  if not bookmarks or #bookmarks == 0 then
    return nil, current_line
  end

  local section_start = current_line
  line_map[section_start] = { type = "section", id = "Bookmarks" }

  local bookmark_rows = {}
  for _, bookmark in ipairs(bookmarks) do
    current_line = current_line + 1
    table.insert(bookmark_rows, ui.row({
      ui.text("  ", {}),
      ui.text(bookmark.name, { hl = "NeoSaplingBranch" }),
      ui.text(" @ " .. bookmark.node, { hl = "NeoSaplingHash" }),
    }))
    line_map[current_line] = { type = "bookmark", bookmark = bookmark }
  end

  local section = ui.fold(
    ui.row({
      ui.text("Bookmarks", { hl = "NeoSaplingSection" }),
      ui.text(" (" .. #bookmarks .. ")"),
    }),
    bookmark_rows,
    { id = "Bookmarks", folded = true }
  )

  return section, current_line
end

--- Build status view component tree
---@param data {status: GroupedStatus, sl_lines?: string[], bookmarks?: Bookmark[], expanded_files?: table<string, FileDiff>}
---@return Component, table<number, Item>, table[] tree, line mapping, extra highlights
function M.build(data)
  local line_map = {}
  local current_line = 1
  local expanded_files = data.expanded_files or {}
  local extra_highlights = {}

  -- Separate modified files into staged vs unstaged
  local unstaged_modified = {}
  local staged_modified = {}
  for _, file in ipairs(data.status.modified or {}) do
    if staged.is_staged(file.path) then
      table.insert(staged_modified, file)
    else
      table.insert(unstaged_modified, file)
    end
  end

  -- Combine added files + staged modified files for Staged section
  local all_staged = {}
  for _, file in ipairs(data.status.added or {}) do
    table.insert(all_staged, file)
  end
  for _, file in ipairs(staged_modified) do
    table.insert(all_staged, file)
  end

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
    current_line,
    expanded_files
  )
  if untracked then
    table.insert(children, untracked)
    current_line = line_after_untracked
    -- Add empty line between sections (accounts for col's new_line before it)
    table.insert(children, ui.text(""))
    current_line = current_line + 1  -- For the empty text itself
    current_line = current_line + 1  -- For col's new_line before next section
  end

  -- Unstaged changes section (modified files not virtually staged)
  local unstaged, line_after_unstaged = build_section(
    "Unstaged changes",
    unstaged_modified,
    "M",
    "NeoSaplingUnstaged",
    "unstaged",
    line_map,
    current_line,
    expanded_files
  )
  if unstaged then
    table.insert(children, unstaged)
    current_line = line_after_unstaged
    table.insert(children, ui.text(""))
    current_line = current_line + 1
    current_line = current_line + 1
  end

  -- Staged changes section (added files + virtually staged modified files)
  local staged_section, line_after_staged = build_section(
    "Staged changes",
    all_staged,
    "A",
    "NeoSaplingStaged",
    "staged",
    line_map,
    current_line,
    expanded_files
  )
  if staged_section then
    table.insert(children, staged_section)
    current_line = line_after_staged
    table.insert(children, ui.text(""))
    current_line = current_line + 1
    current_line = current_line + 1
  end

  -- Smartlog tree section (sl-format graph tree)
  if data.sl_lines and #data.sl_lines > 0 then
    local smartlog_section, line_after_smartlog, sl_highlights = build_smartlog_section(
      data.sl_lines,
      line_map,
      current_line
    )
    if smartlog_section then
      table.insert(children, smartlog_section)
      current_line = line_after_smartlog
      -- Collect extra highlights from sl parser
      for _, hl in ipairs(sl_highlights) do
        table.insert(extra_highlights, hl)
      end
      table.insert(children, ui.text(""))
      current_line = current_line + 1
    end
  end

  -- Bookmarks section (collapsed by default)
  if data.bookmarks and #data.bookmarks > 0 then
    local bookmarks_section, line_after_bookmarks = build_bookmarks_section(
      data.bookmarks,
      line_map,
      current_line
    )
    if bookmarks_section then
      table.insert(children, bookmarks_section)
      current_line = line_after_bookmarks
    end
  end

  return ui.col(children), line_map, extra_highlights
end

return M
