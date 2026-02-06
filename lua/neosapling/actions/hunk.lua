--- Hunk-level action handlers for NeoSapling.
--- Implements hunk discard (reverse-patch revert) for individual diff hunks.
--- @module neosapling.actions.hunk

local M = {}

--- Schedule status buffer refresh
local function schedule_refresh()
  vim.schedule(function()
    local ok, status = pcall(require, "neosapling.status")
    if ok and status.refresh then
      status.refresh()
    end
  end)
end

--- Discard a single hunk by applying a reverse patch to the file on disk.
--- Only works on modified (M) files. For A/? files, shows an informational message.
---@param file FileStatus The file containing the hunk
---@param hunk DiffHunk The hunk to discard
function M.discard(file, hunk)
  -- Validate: hunk revert only works on modified files
  if file.status ~= "M" then
    vim.notify("Hunk revert only works on modified files", vim.log.levels.INFO)
    return
  end

  -- Confirmation with default to No for safety (consistent with file-level discard)
  local choice = vim.fn.confirm("Discard this hunk?", "&Yes\n&No", 2)
  if choice ~= 1 then
    return
  end

  -- Read the current file from disk
  local current_lines = vim.fn.readfile(file.path)
  if not current_lines then
    vim.notify("Failed to read file: " .. file.path, vim.log.levels.ERROR)
    return
  end

  -- Reconstruct the file with this hunk reverted.
  --
  -- The hunk describes the transformation from old -> new.
  -- - hunk.new_start / hunk.new_count describe the region in the NEW (current) file
  -- - hunk.lines contains the diff content:
  --     " " prefix = context line (same in old and new)
  --     "+" prefix = line added in new (not in old) — we REMOVE these
  --     "-" prefix = line removed from old (not in new) — we RESTORE these
  --
  -- To revert: replace the region [new_start, new_start + new_count - 1]
  -- with the original content (context lines + removed lines).

  local new_lines = {}

  -- 1. Copy lines before the hunk region (1 to new_start - 1)
  for i = 1, hunk.new_start - 1 do
    table.insert(new_lines, current_lines[i])
  end

  -- 2. Reconstruct original content from hunk lines
  --    Lines starting with "-" or " " represent original content — include them
  --    Lines starting with "+" represent additions — skip them
  for _, line in ipairs(hunk.lines) do
    local prefix = line:sub(1, 1)
    if prefix == "-" or prefix == " " then
      -- Original content: include without the prefix character
      table.insert(new_lines, line:sub(2))
    end
    -- "+" lines are additions in the new file — skip to revert
  end

  -- 3. Copy lines after the hunk region (new_start + new_count onward)
  for i = hunk.new_start + hunk.new_count, #current_lines do
    table.insert(new_lines, current_lines[i])
  end

  -- Write the reconstructed file
  local write_result = vim.fn.writefile(new_lines, file.path)
  if write_result ~= 0 then
    vim.notify("Failed to write file: " .. file.path, vim.log.levels.ERROR)
    return
  end

  -- Refresh status view to reflect the change
  schedule_refresh()
end

--- Find the hunk associated with the cursor position.
--- If the cursor is on a hunk header line, returns that hunk directly.
--- If on a diff_line, searches backward to find the nearest hunk header.
---@param line_map table<number, Item> Line map from status components
---@param lnum number Current line number (1-indexed)
---@return {file: FileStatus, hunk: DiffHunk}|nil Hunk info or nil if not on a hunk
function M.find_hunk_at_cursor(line_map, lnum)
  local item = line_map[lnum]
  if not item then
    return nil
  end

  if item.type == "hunk" then
    return { file = item.file, hunk = item.hunk }
  end

  if item.type == "diff_line" then
    -- Search backward to find the nearest hunk header
    for i = lnum - 1, 1, -1 do
      local prev = line_map[i]
      if prev and prev.type == "hunk" then
        return { file = prev.file, hunk = prev.hunk }
      end
      -- Stop searching if we hit a non-diff line type
      if prev and prev.type ~= "diff_line" then
        break
      end
    end
  end

  return nil
end

return M
