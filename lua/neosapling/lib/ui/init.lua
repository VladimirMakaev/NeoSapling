--- UI module entry point for NeoSapling.
--- Exports all UI primitives from a single require.
--- @module neosapling.lib.ui

local M = {}

-- Buffer class
M.Buffer = require("neosapling.lib.ui.buffer")

-- Component primitives
local component = require("neosapling.lib.ui.component")
M.text = component.text
M.row = component.row
M.col = component.col
M.fold = component.fold

-- Renderer
local renderer = require("neosapling.lib.ui.renderer")
M.render = renderer.render

-- Highlights
M.highlights = require("neosapling.lib.ui.highlights")

return M
