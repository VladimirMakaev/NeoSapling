--- Renderer module for converting component trees to buffer-ready data.
--- Walks the component tree and produces lines, highlight instructions, and fold regions.
--- @module neosapling.lib.ui.renderer

local M = {}

---@class RenderHighlight
---@field line number 0-indexed line number (for nvim_buf_set_extmark)
---@field col_start number Start column (0-indexed)
---@field col_end number End column (0-indexed, exclusive)
---@field hl string Highlight group name

---@class RenderFold
---@field start number Start line (1-indexed, for foldexpr)
---@field stop number Stop line (1-indexed, for foldexpr)

---@class RenderResult
---@field lines string[] Lines for nvim_buf_set_lines
---@field highlights RenderHighlight[] Highlight instructions
---@field folds RenderFold[] Fold regions

---@class RenderState
---@field lines string[] Current lines being built
---@field highlights RenderHighlight[] Collected highlights
---@field folds RenderFold[] Collected fold regions
---@field line number Current line index (1-indexed for Lua array)
---@field col number Current column position in current line (0-indexed)

--- Create initial render state
---@return RenderState
local function create_state()
  return {
    lines = { "" },
    highlights = {},
    folds = {},
    line = 1,
    col = 0,
  }
end

--- Render a text node
---@param node table Text component
---@param state RenderState Current render state
local function render_text(node, state)
  local content = node.content or ""
  local start_col = state.col

  -- Append content to current line
  state.lines[state.line] = state.lines[state.line] .. content
  state.col = state.col + #content

  -- Record highlight if specified
  if node.options and node.options.hl and #content > 0 then
    table.insert(state.highlights, {
      line = state.line - 1, -- 0-indexed for API
      col_start = start_col,
      col_end = state.col,
      hl = node.options.hl,
    })
  end
end

--- Forward declaration for mutual recursion
local render_node

--- Render a row node (horizontal layout)
---@param node table Row component
---@param state RenderState Current render state
local function render_row(node, state)
  -- Render children sequentially on same line
  for _, child in ipairs(node.children) do
    render_node(child, state)
  end
end

--- Start a new line in the render state
---@param state RenderState Current render state
local function new_line(state)
  table.insert(state.lines, "")
  state.line = state.line + 1
  state.col = 0
end

--- Render a col node (vertical layout)
---@param node table Col component
---@param state RenderState Current render state
local function render_col(node, state)
  for i, child in ipairs(node.children) do
    -- Insert new line before each child except the first
    if i > 1 then
      new_line(state)
    end
    render_node(child, state)
  end
end

--- Render a fold node (foldable section)
---@param node table Fold component
---@param state RenderState Current render state
local function render_fold(node, state)
  -- Record start line for fold region (1-indexed)
  local fold_start = state.line

  -- Render all children (header is first, body follows)
  for i, child in ipairs(node.children) do
    if i > 1 then
      new_line(state)
    end
    render_node(child, state)
  end

  -- Record fold region (only if there are body children, i.e. more than header)
  if #node.children > 1 then
    table.insert(state.folds, {
      start = fold_start,
      stop = state.line,
    })
  end
end

--- Render a single node by dispatching on tag
---@param node table Component node
---@param state RenderState Current render state
render_node = function(node, state)
  if not node or not node.tag then
    return
  end

  if node.tag == "text" then
    render_text(node, state)
  elseif node.tag == "row" then
    render_row(node, state)
  elseif node.tag == "col" then
    render_col(node, state)
  elseif node.tag == "fold" then
    render_fold(node, state)
  end
end

--- Render a component tree to buffer-ready data
---@param root table Root component node
---@return RenderResult
function M.render(root)
  local state = create_state()

  if root then
    render_node(root, state)
  end

  return {
    lines = state.lines,
    highlights = state.highlights,
    folds = state.folds,
  }
end

return M
