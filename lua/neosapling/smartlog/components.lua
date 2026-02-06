--- Component builder for smartlog view.
--- Transforms extended commit data into a component tree with line mapping.
--- @module neosapling.smartlog.components

local ui = require("neosapling.lib.ui")
local graph = require("neosapling.smartlog.graph")

local M = {}

---Build smartlog view component tree
---@param data {commits: CommitExtended[]}
---@return Component, table<number, Item> tree and line mapping
function M.build(data)
  local line_map = {}
  local current_line = 1
  local commits = data.commits or {}

  local children = {}

  -- Header
  table.insert(children, ui.row({
    ui.text("Smartlog", { hl = "NeoSaplingHeader" }),
  }))
  current_line = current_line + 1

  -- Empty line after header
  table.insert(children, ui.text(""))
  current_line = current_line + 1

  if #commits == 0 then
    table.insert(children, ui.text("  No commits found"))
    return ui.col(children), line_map
  end

  -- Assign graph columns
  local commit_index, _ = graph.assign_columns(commits)

  -- Build commit rows
  for _, commit in ipairs(commits) do
    local prefix = graph.build_prefix(commit, {}, commit_index)

    -- Determine graphnode highlight
    local graphnode_hl = "NeoSaplingHash"
    if commit.graphnode == "@" then
      graphnode_hl = "NeoSaplingCurrent"
    elseif commit.graphnode == "x" then
      graphnode_hl = "NeoSaplingObsolete"
    end

    -- Build row parts
    local row_parts = {
      ui.text(prefix, {}),
      ui.text(commit.graphnode .. " ", { hl = graphnode_hl }),
      ui.text(commit.node .. " ", { hl = "NeoSaplingHash" }),
    }

    -- Add bookmarks if present
    if commit.bookmarks and #commit.bookmarks > 0 then
      table.insert(row_parts, ui.text("[" .. table.concat(commit.bookmarks, ", ") .. "] ", { hl = "NeoSaplingBranch" }))
    end

    -- Add author, date, and description
    table.insert(row_parts, ui.text(commit.author, { hl = "NeoSaplingAuthor" }))
    table.insert(row_parts, ui.text(" " .. commit.date .. " ", { hl = "NeoSaplingDate" }))
    table.insert(row_parts, ui.text(commit.desc, {}))

    table.insert(children, ui.row(row_parts))
    line_map[current_line] = { type = "commit", commit = commit }
    current_line = current_line + 1
  end

  return ui.col(children), line_map
end

return M
