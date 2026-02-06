--- Smartlog buffer module for NeoSapling.
--- Orchestrates buffer lifecycle, data fetch, render, and keymap management.
--- @module neosapling.smartlog

local ui = require("neosapling.lib.ui")
local neosapling = require("neosapling")
local components = require("neosapling.smartlog.components")

local M = {}

-- Module state
local smartlog_buffer = nil
local current_data = nil
local line_map = {}

-- Version token for preventing stale data from async operations
local current_version = nil

--- Setup buffer options and keymaps
local function setup_buffer()
  if not smartlog_buffer or not smartlog_buffer:is_valid() then
    return
  end

  local bufnr = smartlog_buffer.handle

  -- Set filetype
  vim.api.nvim_buf_set_option(bufnr, "filetype", "neosapling")

  -- q closes smartlog and returns to previous buffer
  vim.keymap.set("n", "q", function()
    M.close()
  end, { buffer = bufnr, desc = "Close smartlog" })

  -- ? opens help popup
  vim.keymap.set("n", "?", function()
    require("neosapling.popups.help").create()
  end, { buffer = bufnr, desc = "Open help popup" })

  -- d opens diff popup (placeholder - implemented in Plan 06-03)
  vim.keymap.set("n", "d", function()
    local lnum = vim.fn.line(".")
    local item = line_map[lnum]
    if item and item.type == "commit" then
      -- Diff popup will be implemented in 06-03
      vim.notify("Diff popup coming in next plan", vim.log.levels.INFO)
    end
  end, { buffer = bufnr, desc = "Open diff popup" })
end

--- Internal: Render current data to buffer
function M._render()
  if not current_data or not smartlog_buffer or not smartlog_buffer:is_valid() then
    return
  end

  local tree, new_line_map = components.build(current_data)
  line_map = new_line_map

  local result = ui.render(tree)
  smartlog_buffer:set_lines(result.lines)
  smartlog_buffer:clear_highlights()

  for _, hl in ipairs(result.highlights) do
    smartlog_buffer:add_highlight(hl.line, hl.col_start, hl.col_end, hl.hl)
  end
end

--- Refresh smartlog data and re-render
function M.refresh()
  local version = vim.loop.now()
  current_version = version

  neosapling.sl.smartlog_extended(function(commits, err)
    if current_version ~= version then return end -- Stale
    if err then
      vim.notify("NeoSapling: " .. err, vim.log.levels.ERROR)
      return
    end

    current_data = { commits = commits }

    vim.schedule(function()
      M._render()
    end)
  end)
end

--- Open the smartlog buffer (full-screen in current window)
function M.open()
  -- Create or get existing buffer
  if not smartlog_buffer or not smartlog_buffer:is_valid() then
    smartlog_buffer = ui.Buffer:new("neosapling://smartlog")
    setup_buffer()
  end

  -- Show full-screen (take over current window)
  smartlog_buffer:show("current")
  M.refresh()
end

--- Close the smartlog buffer
function M.close()
  if smartlog_buffer and smartlog_buffer:is_valid() then
    -- Go to previous buffer BEFORE destroying (Pitfall #1 from RESEARCH.md)
    vim.cmd("bprevious")
    smartlog_buffer:destroy()
    smartlog_buffer = nil
  end
  current_data = nil
  line_map = {}
end

--- Get the current line map (for external access)
---@return table<number, Item>
function M.get_line_map()
  return line_map
end

return M
