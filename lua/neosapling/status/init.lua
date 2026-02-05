--- Status buffer module for NeoSapling.
--- Orchestrates buffer lifecycle, data fetch, render, and fold management.
--- @module neosapling.status

local ui = require("neosapling.lib.ui")
local neosapling = require("neosapling")
local components = require("neosapling.status.components")

local M = {}

-- Module state
local status_buffer = nil
local current_data = nil
local line_map = {}
local fold_regions = {}
local expanded_files = {}  -- path -> FileDiff cache

-- Fold level cache for performance (Pitfall #5 from RESEARCH.md)
local fold_level_cache = {}
local cache_valid = false

--- Global foldexpr function (must be global for v:lua access)
---@param lnum number Line number (1-indexed)
---@return string Fold level expression
function _G.neosapling_status_foldexpr(lnum)
  if not cache_valid then
    fold_level_cache = {}
    for _, region in ipairs(fold_regions) do
      fold_level_cache[region.start] = ">1"
      for i = region.start + 1, region.stop do
        fold_level_cache[i] = "1"
      end
    end
    cache_valid = true
  end
  return fold_level_cache[lnum] or "0"
end

--- Toggle file expansion (show/hide inline diff preview)
---@param file FileStatus File to toggle
local function toggle_file_expand(file)
  local path = file.path

  -- If already expanded, collapse
  if expanded_files[path] then
    expanded_files[path] = nil
    M._render()
    return
  end

  -- Fetch diff for this file
  neosapling.sl.diff({ files = { path } }, function(diffs, err)
    if err or #diffs == 0 then
      -- No diff available (new file, etc.) - just mark as expanded with empty diff
      vim.schedule(function()
        expanded_files[path] = { hunks = {} }
        M._render()
      end)
      return
    end

    vim.schedule(function()
      expanded_files[path] = diffs[1]
      M._render()
    end)
  end)
end

--- Setup buffer options and keymaps
local function setup_buffer()
  if not status_buffer or not status_buffer:is_valid() then
    return
  end

  local bufnr = status_buffer.handle

  -- Set filetype
  vim.api.nvim_buf_set_option(bufnr, "filetype", "neosapling")

  -- Tab toggles fold or file expansion based on cursor position
  vim.keymap.set("n", "<Tab>", function()
    local lnum = vim.fn.line(".")
    local item = line_map[lnum]

    if item and item.type == "file" then
      -- Toggle file diff expansion
      toggle_file_expand(item.file)
    elseif item and item.type == "section" then
      -- Toggle section fold
      local foldclosed = vim.fn.foldclosed(".")
      if foldclosed == -1 then
        vim.cmd("normal! zc")
      else
        vim.cmd("normal! zo")
      end
    else
      -- Default: toggle fold if on a fold
      local foldclosed = vim.fn.foldclosed(".")
      if foldclosed == -1 then
        pcall(vim.cmd, "normal! zc")
      else
        vim.cmd("normal! zo")
      end
    end
  end, { buffer = bufnr, desc = "Toggle fold or file expansion" })

  -- Help popup (? key)
  vim.keymap.set("n", "?", function()
    require("neosapling.popups.help").create()
  end, { buffer = bufnr, desc = "Open help popup" })

  -- Commit popup (c key)
  vim.keymap.set("n", "c", function()
    require("neosapling.popups.commit").create()
  end, { buffer = bufnr, desc = "Open commit popup" })

  -- Close buffer (q key)
  vim.keymap.set("n", "q", function()
    require("neosapling.status").close()
  end, { buffer = bufnr, desc = "Close status buffer" })

  -- Stage file (s key)
  vim.keymap.set("n", "s", function()
    local context = require("neosapling.status.context")
    local file_actions = require("neosapling.actions.file")
    local item = context.get_item_at_cursor(line_map)
    if item and item.type == "file" and item.file then
      file_actions.stage(item.file)
    end
  end, { buffer = bufnr, desc = "Stage file" })

  -- Unstage file (u key)
  vim.keymap.set("n", "u", function()
    local context = require("neosapling.status.context")
    local file_actions = require("neosapling.actions.file")
    local item = context.get_item_at_cursor(line_map)
    if item and item.type == "file" and item.file then
      file_actions.unstage(item.file)
    end
  end, { buffer = bufnr, desc = "Unstage file" })

  -- Discard changes (x key)
  vim.keymap.set("n", "x", function()
    local context = require("neosapling.status.context")
    local file_actions = require("neosapling.actions.file")
    local item = context.get_item_at_cursor(line_map)
    if item and item.type == "file" and item.file then
      file_actions.discard(item.file)
    end
  end, { buffer = bufnr, desc = "Discard changes" })
end

--- Setup folds for status buffer
---@param folds RenderFold[] Fold regions from renderer
local function setup_folds(folds)
  fold_regions = folds
  cache_valid = false -- Invalidate cache

  local win = vim.fn.bufwinid(status_buffer.handle)
  if win ~= -1 then
    vim.api.nvim_win_set_option(win, "foldmethod", "expr")
    vim.api.nvim_win_set_option(win, "foldexpr", "v:lua.neosapling_status_foldexpr(v:lnum)")
    vim.api.nvim_win_set_option(win, "foldlevel", 99) -- Start with all open
    vim.api.nvim_win_set_option(win, "foldenable", true)
  end
end

--- Close default-collapsed sections (Recent Stacks and Bookmarks)
---@param folds RenderFold[] Fold regions from renderer
local function close_default_collapsed(folds)
  local win = vim.fn.bufwinid(status_buffer.handle)
  if win == -1 then return end

  vim.schedule(function()
    if not status_buffer or not status_buffer:is_valid() then return end

    -- Find and close sections that should be collapsed by default
    for _, region in ipairs(folds) do
      local item = line_map[region.start]
      if item and item.type == "section" and (item.id == "Recent Stacks" or item.id == "Bookmarks") then
        vim.api.nvim_win_call(win, function()
          vim.fn.cursor(region.start, 1)
          pcall(vim.cmd, "normal! zc")
        end)
      end
    end
  end)
end

--- Internal: Render current data to buffer
function M._render()
  if not current_data or not status_buffer or not status_buffer:is_valid() then
    return
  end

  -- Invalidate fold cache before render
  cache_valid = false

  -- Build component tree with expanded files
  local build_data = {
    status = current_data.status,
    commits = current_data.commits,
    bookmarks = current_data.bookmarks,
    expanded_files = expanded_files,
  }
  local tree, new_line_map = components.build(build_data)
  line_map = new_line_map

  -- Render to buffer
  local result = ui.render(tree)
  status_buffer:set_lines(result.lines)
  status_buffer:clear_highlights()

  for _, hl in ipairs(result.highlights) do
    status_buffer:add_highlight(hl.line, hl.col_start, hl.col_end, hl.hl)
  end

  -- Setup folds
  setup_folds(result.folds)

  -- Close sections that should be collapsed by default
  close_default_collapsed(result.folds)
end

-- Version token for preventing stale data from async operations
local current_version = nil

--- Refresh status data and re-render
function M.refresh()
  local version = vim.loop.now()
  current_version = version

  neosapling.sl.status(function(grouped_status, err1)
    if current_version ~= version then return end -- Stale
    if err1 then
      vim.notify("NeoSapling: " .. err1, vim.log.levels.ERROR)
      return
    end

    neosapling.sl.smartlog(function(commits, err2)
      if current_version ~= version then return end -- Stale
      if err2 then
        -- Non-fatal: show status without smartlog
        commits = {}
      end

      neosapling.sl.bookmarks(function(bookmarks, err3)
        if current_version ~= version then return end -- Stale
        if err3 then
          -- Non-fatal: show status without bookmarks
          bookmarks = {}
        end

        current_data = {
          status = grouped_status,
          commits = commits,
          bookmarks = bookmarks,
        }

        vim.schedule(function()
          M._render()
        end)
      end)
    end)
  end)
end

--- Open the status buffer
function M.open()
  -- Create or get existing buffer
  if not status_buffer or not status_buffer:is_valid() then
    status_buffer = ui.Buffer:new("neosapling://status")
    setup_buffer()
  end

  status_buffer:show("split")
  M.refresh()
end

--- Close the status buffer
function M.close()
  if status_buffer and status_buffer:is_valid() then
    status_buffer:destroy()
    status_buffer = nil
  end
  current_data = nil
  line_map = {}
  fold_regions = {}
  expanded_files = {}
  cache_valid = false
end

--- Get the current line map (for context module)
---@return table<number, Item>
function M.get_line_map()
  return line_map
end

return M
