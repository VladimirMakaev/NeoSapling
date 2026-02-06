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

-- Extended template with parent data
-- Format: pipe-separated fields (8 total), each entry on its own line
-- Fields: node|graphnode|author|date|desc|bookmarks|p1node|p2node
M.TEMPLATE_EXTENDED = table.concat({
  "{node|short}",      -- 12-char hash
  "{graphnode}",       -- Graph character (@, o, x)
  "{author|user}",     -- Username only
  "{date|age}",        -- Relative date
  "{desc|firstline}",  -- First line of commit message
  "{bookmarks}",       -- Space-separated bookmarks
  "{p1node|short}",    -- First parent hash (12 chars, or 000000000000 for root)
  "{p2node|short}",    -- Second parent hash (for merges, 000000000000 if none)
}, "|") .. "\\n"

---@class Commit
---@field node string Short hash (12 characters)
---@field graphnode string Graph character (@ for current, o for normal, x for obsolete)
---@field author string Author username
---@field date string Relative date (e.g., "2 hours ago")
---@field desc string First line of commit message
---@field bookmarks string[] Array of bookmark names

---@class CommitExtended : Commit
---@field p1node string|nil First parent node (nil if no parent or root commit)
---@field p2node string|nil Second parent node (nil if no merge)

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

---Parse a single extended smartlog line with parent data
---
---@param line string Single line of extended template output
---@return CommitExtended|nil Parsed commit or nil if invalid
function M.parse_line_extended(line)
  -- Skip empty lines
  if not line or line == "" then
    return nil
  end

  local parts = vim.split(line, "|", { plain = true })

  -- Need at least 8 parts for valid extended commit
  if #parts < 8 then
    return nil
  end

  -- Parse bookmarks (space-separated in field 6)
  local bookmarks_str = parts[6] or ""
  local bookmarks = vim.split(bookmarks_str, " ", { plain = true, trimempty = true })

  -- Parse parent nodes (convert all-zeros to nil)
  local p1 = parts[7]
  local p2 = parts[8]
  if p1 and p1:match("^0+$") then p1 = nil end
  if p2 and p2:match("^0+$") then p2 = nil end

  return {
    node = parts[1],
    graphnode = parts[2],
    author = parts[3],
    date = parts[4],
    desc = parts[5],
    bookmarks = bookmarks,
    p1node = p1,
    p2node = p2,
  }
end

---Parse extended smartlog template output
---
---Parses multiple lines of extended template output into an array of CommitExtended objects.
---
---@param lines string[] Raw smartlog output lines
---@return CommitExtended[] Parsed commits
function M.parse_extended(lines)
  local commits = {}

  -- Handle nil or empty input
  if not lines or #lines == 0 then
    return commits
  end

  for _, line in ipairs(lines) do
    local commit = M.parse_line_extended(line)
    if commit then
      table.insert(commits, commit)
    end
  end

  return commits
end

return M
