-- Status output parser for Sapling VCS
-- Parses `sl status --print0` output into structured Lua tables

local M = {}

---@class FileStatus
---@field status string Single-char status code (M, A, R, ?, !, I, C)
---@field path string File path

---Parse sl status --print0 output
---
---The --print0 format outputs entries separated by NUL characters.
---Each entry format: "X path" where X is the status character followed by a space.
---
---Note: Vim internally converts NUL (0x00) to SOH (0x01) in strings,
---so we handle both separators for compatibility.
---
---@param lines string[] Raw output lines from CLI (may span multiple lines)
---@return FileStatus[] Parsed file statuses
function M.parse(lines)
  local result = {}

  -- Handle nil or empty input
  if not lines or #lines == 0 then
    return result
  end

  -- Join lines and normalize separators
  -- Vim converts NUL (0x00) to SOH (0x01) internally, so handle both
  local raw = table.concat(lines, "\n")
  -- Replace SOH with NUL for consistent splitting
  raw = raw:gsub("\1", "\0")
  local entries = vim.split(raw, "\0", { plain = true, trimempty = true })

  for _, entry in ipairs(entries) do
    -- Skip empty entries
    if entry ~= "" then
      -- Format: "X path" where X is status char
      local status = entry:sub(1, 1)
      local path = entry:sub(3) -- Skip status char and space

      if status ~= "" and path ~= "" then
        table.insert(result, {
          status = status,
          path = path,
        })
      end
    end
  end

  return result
end

---@class GroupedStatus
---@field modified FileStatus[] Files with status M (modified)
---@field added FileStatus[] Files with status A (added)
---@field removed FileStatus[] Files with status R (removed)
---@field unknown FileStatus[] Files with status ? (not tracked)
---@field missing FileStatus[] Files with status ! (missing/deleted outside sl)
---@field ignored FileStatus[] Files with status I (ignored)
---@field clean FileStatus[] Files with status C (clean)

---Group status entries by type
---
---Takes the output of parse() and groups files by their status code.
---
---@param statuses FileStatus[] Parsed file statuses from parse()
---@return GroupedStatus Grouped statuses by type
function M.group(statuses)
  local groups = {
    modified = {}, -- M
    added = {},    -- A
    removed = {},  -- R
    unknown = {},  -- ?
    missing = {},  -- !
    ignored = {},  -- I
    clean = {},    -- C
  }

  -- Map status codes to group names
  local status_map = {
    M = "modified",
    A = "added",
    R = "removed",
    ["?"] = "unknown",
    ["!"] = "missing",
    I = "ignored",
    C = "clean",
  }

  for _, entry in ipairs(statuses) do
    local group = status_map[entry.status]
    if group then
      table.insert(groups[group], entry)
    end
  end

  return groups
end

return M
