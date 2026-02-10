-- Diff output parser for Sapling VCS
-- Parses `sl diff --git` output into structured Lua tables

local M = {}

-- Pattern constants for git extended diff format
M.DIFF_HEADER = "^diff %-%-git a/(.-) b/(.-)$"
M.HUNK_HEADER = "^@@%s+%-(%d+),?(%d*)%s+%+(%d+),?(%d*)%s+@@(.*)$"

---@class DiffHunk
---@field old_start number Starting line in old file
---@field old_count number Number of lines in old file (default 1)
---@field new_start number Starting line in new file
---@field new_count number Number of lines in new file (default 1)
---@field header string Function context from @@ line (may be empty)
---@field lines string[] Diff content lines (context, additions, deletions)

---@class FileDiff
---@field from_path string Source file path (from a/)
---@field to_path string Destination file path (from b/)
---@field hunks DiffHunk[] Array of diff hunks

---Parse sl diff --git output
---
---Parses git extended diff format into structured FileDiff objects.
---Each file has a diff header and zero or more hunks containing the actual changes.
---
---@param lines string[] Raw diff output lines
---@return FileDiff[] Parsed file diffs
function M.parse(lines)
  local files = {}

  -- Handle nil or empty input
  if not lines or #lines == 0 then
    return files
  end

  local current_file = nil
  local current_hunk = nil

  for _, line in ipairs(lines) do
    -- Check for new file diff header
    local from, to = line:match(M.DIFF_HEADER)
    if from then
      -- Save previous file if exists
      if current_hunk and current_file then
        table.insert(current_file.hunks, current_hunk)
      end
      if current_file then
        table.insert(files, current_file)
      end

      -- Start new file
      current_file = {
        from_path = from,
        to_path = to,
        hunks = {},
      }
      current_hunk = nil
    elseif current_file then
      -- Check for hunk header
      local old_start, old_count, new_start, new_count, context =
        line:match(M.HUNK_HEADER)

      if old_start then
        -- Save previous hunk if exists
        if current_hunk then
          table.insert(current_file.hunks, current_hunk)
        end

        -- Start new hunk
        current_hunk = {
          old_start = tonumber(old_start),
          old_count = tonumber(old_count) or 1,
          new_start = tonumber(new_start),
          new_count = tonumber(new_count) or 1,
          header = context or "",
          lines = {},
        }
      elseif current_hunk then
        -- Collect ALL lines within a hunk (including lines starting with --- or +++)
        -- These are real diff content, e.g. deletion of "---@param" produces "----@param"
        table.insert(current_hunk.lines, line)
      end
      -- Lines between "diff --git" and first "@@" (like --- a/path, +++ b/path,
      -- old mode, new mode, index, etc.) are silently skipped: current_hunk is nil
      -- so neither the hunk header match nor the elseif branch applies.
    end
  end

  -- Finalize last hunk and file
  if current_hunk and current_file then
    table.insert(current_file.hunks, current_hunk)
  end
  if current_file then
    table.insert(files, current_file)
  end

  return files
end

return M
