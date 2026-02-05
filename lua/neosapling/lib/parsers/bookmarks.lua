-- Bookmarks parser for Sapling VCS
-- Parses `sl bookmark -T TEMPLATE` output

local M = {}

-- Template: bookmark name and short hash, separated by |
M.TEMPLATE = "{bookmark}|{node|short}\\n"

---@class Bookmark
---@field name string Bookmark name
---@field node string Short commit hash

---Parse a single bookmark line
---@param line string Template output line
---@return Bookmark|nil
function M.parse_line(line)
  if not line or line == "" then return nil end

  local parts = vim.split(line, "|", { plain = true })
  if #parts < 2 then return nil end

  return {
    name = parts[1],
    node = parts[2],
  }
end

---Parse bookmark template output
---@param lines string[] Raw bookmark output lines
---@return Bookmark[]
function M.parse(lines)
  local bookmarks = {}
  if not lines or #lines == 0 then return bookmarks end

  for _, line in ipairs(lines) do
    local bookmark = M.parse_line(line)
    if bookmark then
      table.insert(bookmarks, bookmark)
    end
  end

  return bookmarks
end

return M
