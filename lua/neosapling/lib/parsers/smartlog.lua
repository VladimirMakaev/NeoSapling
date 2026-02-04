-- Smartlog output parser for Sapling VCS
-- Parses `sl smartlog -T TEMPLATE` output into structured Lua tables

local M = {}

-- Template constant for use with sl smartlog -T
-- Format: pipe-separated fields, each entry on its own line
-- Fields: node|graphnode|author|date|desc|bookmarks
M.TEMPLATE = table.concat({
  "{node|short}",      -- 12-char hash
  "{graphnode}",       -- Graph character (@, o, x)
  "{author|user}",     -- Username only
  "{date|age}",        -- Relative date
  "{desc|firstline}",  -- First line of commit message
  "{bookmarks}",       -- Space-separated bookmarks
}, "|") .. "\\n"

---@class Commit
---@field node string Short hash (12 characters)
---@field graphnode string Graph character (@ for current, o for normal, x for obsolete)
---@field author string Author username
---@field date string Relative date (e.g., "2 hours ago")
---@field desc string First line of commit message
---@field bookmarks string[] Array of bookmark names

---Parse a single smartlog line
---
---@param line string Single line of template output
---@return Commit|nil Parsed commit or nil if invalid
function M.parse_line(line)
  -- Skip empty lines
  if not line or line == "" then
    return nil
  end

  local parts = vim.split(line, "|", { plain = true })

  -- Need at least 6 parts for valid commit
  if #parts < 6 then
    return nil
  end

  -- Parse bookmarks (space-separated in last field)
  local bookmarks_str = parts[6] or ""
  local bookmarks = vim.split(bookmarks_str, " ", { plain = true, trimempty = true })

  return {
    node = parts[1],
    graphnode = parts[2],
    author = parts[3],
    date = parts[4],
    desc = parts[5],
    bookmarks = bookmarks,
  }
end

---Parse smartlog template output
---
---Parses multiple lines of template output into an array of Commit objects.
---
---@param lines string[] Raw smartlog output lines
---@return Commit[] Parsed commits
function M.parse(lines)
  local commits = {}

  -- Handle nil or empty input
  if not lines or #lines == 0 then
    return commits
  end

  for _, line in ipairs(lines) do
    local commit = M.parse_line(line)
    if commit then
      table.insert(commits, commit)
    end
  end

  return commits
end

return M
