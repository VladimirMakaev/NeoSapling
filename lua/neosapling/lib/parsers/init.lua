-- Parsers module entry point
-- Exports all output parsers for Sapling CLI commands

local M = {}

-- Load parser modules
M.status = require("neosapling.lib.parsers.status")
M.diff = require("neosapling.lib.parsers.diff")
M.smartlog = require("neosapling.lib.parsers.smartlog")
M.bookmarks = require("neosapling.lib.parsers.bookmarks")
M.smartlog_ssl = require("neosapling.lib.parsers.smartlog_ssl")

return M
