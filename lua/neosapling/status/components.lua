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

--- Build a commits section showing the current stack
---@param commits Commit[] Commits from smartlog
---@param line_map table<number, Item> Line map to populate
---@param current_line number Current line number (1-indexed)
---@return Component|nil, number Commits section (nil if empty) and updated line number
local function build_commits_section(commits, line_map, current_line)
  -- Filter to current stack: commits where graphnode is not "x" (obsolete)
  local stack_commits = {}
  for _, commit in ipairs(commits) do
    if commit.graphnode ~= "x" then
      table.insert(stack_commits, commit)
    end
  end

  if #stack_commits == 0 then
    return nil, current_line
  end

  local section_start = current_line
  line_map[section_start] = { type = "section", id = "commits" }

  local commit_rows = {}
  for _, commit in ipairs(stack_commits) do
    current_line = current_line + 1
    local graphnode_hl = commit.graphnode == "@" and "NeoSaplingCurrent" or "NeoSaplingHash"
    table.insert(commit_rows, ui.row({
      ui.text("  " .. commit.graphnode .. " ", { hl = graphnode_hl }),
      ui.text(commit.node .. " ", { hl = "NeoSaplingHash" }),
      ui.text(commit.desc),
    }))
    line_map[current_line] = { type = "commit", commit = commit }
  end

  local section = ui.fold(
    ui.row({
      ui.text("Current Stack", { hl = "NeoSaplingSection" }),
      ui.text(" (" .. #stack_commits .. " commits)"),
    }),
    commit_rows,
    { id = "commits" }
  )

  return section, current_line
end

--- Build a recent stacks section showing obsolete commits
---@param commits Commit[] Commits from smartlog
---@param line_map table<number, Item> Line map to populate
---@param current_line number Current line number (1-indexed)
---@return Component|nil, number Recent stacks section (nil if empty) and updated line number
local function build_recent_stacks_section(commits, line_map, current_line)
  -- Filter to obsolete commits: graphnode == "x"
  local obsolete_commits = {}
  for _, commit in ipairs(commits) do
    if commit.graphnode == "x" then
      table.insert(obsolete_commits, commit)
    end
  end

  if #obsolete_commits == 0 then
    return nil, current_line
  end

  local section_start = current_line
  line_map[section_start] = { type = "section", id = "Recent Stacks" }

  local commit_rows = {}
  for _, commit in ipairs(obsolete_commits) do
    current_line = current_line + 1
    table.insert(commit_rows, ui.row({
      ui.text("  x ", { hl = "NeoSaplingHash" }),
      ui.text(commit.node .. " ", { hl = "NeoSaplingHash" }),
      ui.text(commit.desc),
    }))
    line_map[current_line] = { type = "commit", commit = commit, section = "recent" }
  end

  local section = ui.fold(
    ui.row({
      ui.text("Recent Stacks", { hl = "NeoSaplingSection" }),
      ui.text(" (" .. #obsolete_commits .. ")"),
    }),
    commit_rows,
    { id = "Recent Stacks", folded = true }
  )

  return section, current_line
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
---@param data {status: GroupedStatus, commits?: Commit[], bookmarks?: Bookmark[], expanded_files?: table<string, FileDiff>}
---@return Component, table<number, Item> tree and line mapping
function M.build(data)
  local line_map = {}
  local current_line = 1
  local expanded_files = data.expanded_files or {}

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

  -- Unstaged changes section (modified status = M)
  local unstaged, line_after_unstaged = build_section(
    "Unstaged changes",
    data.status.modified,
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

  -- Staged changes section (added status = A)
  local staged, line_after_staged = build_section(
    "Staged changes",
    data.status.added,
    "A",
    "NeoSaplingStaged",
    "staged",
    line_map,
    current_line,
    expanded_files
  )
  if staged then
    table.insert(children, staged)
    current_line = line_after_staged
    table.insert(children, ui.text(""))
    current_line = current_line + 1
    current_line = current_line + 1
  end

  -- Current Stack section (commits from smartlog)
  if data.commits and #data.commits > 0 then
    local commits_section, line_after_commits = build_commits_section(
      data.commits,
      line_map,
      current_line
    )
    if commits_section then
      table.insert(children, commits_section)
      current_line = line_after_commits
      table.insert(children, ui.text(""))
      current_line = current_line + 1
    end
  end

  -- Recent Stacks section (obsolete commits, collapsed by default)
  if data.commits and #data.commits > 0 then
    local recent_section, line_after_recent = build_recent_stacks_section(
      data.commits,
      line_map,
      current_line
    )
    if recent_section then
      table.insert(children, recent_section)
      current_line = line_after_recent
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

  return ui.col(children), line_map
end

return M
