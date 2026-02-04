--- Component primitives for building declarative UI trees.
--- Components are pure data structures (no side effects).
--- @module neosapling.lib.ui.component

local M = {}

--- @class Component
--- @field tag string Component type identifier
--- @field children Component[] Child components
--- @field options table Component-specific options
--- @field content string|nil Text content (only for text nodes)

--- @class TextOptions
--- @field hl string|nil Highlight group name

--- @class RowOptions
--- @field hl string|nil Line highlight group name

--- @class ColOptions
--- @field hl string|nil Highlight group name

--- @class FoldOptions
--- @field folded boolean|nil Whether fold is collapsed (default: false)
--- @field id string|nil Unique identifier for fold state persistence

--- Create a text node component.
--- Text nodes are leaf nodes that contain actual content to render.
--- @param content string The text content
--- @param opts TextOptions|nil Optional configuration
--- @return Component
function M.text(content, opts)
  opts = opts or {}
  return {
    tag = "text",
    content = content,
    children = {},
    options = {
      hl = opts.hl,
    },
  }
end

--- Create a row component for horizontal layout.
--- Children are rendered on the same line, left to right.
--- @param children Component[] Child components to layout horizontally
--- @param opts RowOptions|nil Optional configuration
--- @return Component
function M.row(children, opts)
  opts = opts or {}
  return {
    tag = "row",
    content = nil,
    children = children or {},
    options = {
      hl = opts.hl,
    },
  }
end

--- Create a col component for vertical layout.
--- Children are rendered on separate lines, top to bottom.
--- @param children Component[] Child components to layout vertically
--- @param opts ColOptions|nil Optional configuration
--- @return Component
function M.col(children, opts)
  opts = opts or {}
  return {
    tag = "col",
    content = nil,
    children = children or {},
    options = opts,
  }
end

--- Create a foldable section component.
--- The header is always visible; body children collapse when folded.
--- @param header Component The header component (always visible)
--- @param children Component[] Body components (collapsible)
--- @param opts FoldOptions|nil Optional configuration
--- @return Component
function M.fold(header, children, opts)
  opts = opts or {}
  -- Header is first child, body children follow
  local all_children = { header }
  for _, child in ipairs(children or {}) do
    table.insert(all_children, child)
  end
  return {
    tag = "fold",
    content = nil,
    children = all_children,
    options = {
      folded = opts.folded or false,
      id = opts.id,
    },
  }
end

return M
