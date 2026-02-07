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

-- Track initial open vs refresh to avoid re-collapsing default-collapsed sections
local is_initial_open = false

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
  vim.bo[bufnr].filetype = "neosapling"

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

  -- Discard changes (x key) — context-sensitive: file-level or hunk-level
  vim.keymap.set("n", "x", function()
    local context = require("neosapling.status.context")
    local item = context.get_item_at_cursor(line_map)
    if not item then return end

    if item.type == "file" then
      -- Existing file-level discard
      local file_actions = require("neosapling.actions.file")
      file_actions.discard(item.file)
    elseif item.type == "hunk" or item.type == "diff_line" then
      -- Hunk-level discard
      local hunk_actions = require("neosapling.actions.hunk")
      local hunk_info = hunk_actions.find_hunk_at_cursor(line_map, vim.fn.line("."))
      if hunk_info then
        hunk_actions.discard(hunk_info.file, hunk_info.hunk)
      end
    end
  end, { buffer = bufnr, desc = "Discard changes or hunk" })

  -- Navigate to previous hunk header ({ key)
  vim.keymap.set("n", "{", function()
    local lnum = vim.fn.line(".")
    for i = lnum - 1, 1, -1 do
      local item = line_map[i]
      if item and item.type == "hunk" then
        vim.fn.cursor(i, 1)
        return
      end
    end
  end, { buffer = bufnr, desc = "Previous hunk" })

  -- Navigate to next hunk header (} key)
  vim.keymap.set("n", "}", function()
    local lnum = vim.fn.line(".")
    local total = vim.api.nvim_buf_line_count(bufnr)
    for i = lnum + 1, total do
      local item = line_map[i]
      if item and item.type == "hunk" then
        vim.fn.cursor(i, 1)
        return
      end
    end
  end, { buffer = bufnr, desc = "Next hunk" })

  -- Enter: goto commit or bookmark under cursor
  vim.keymap.set("n", "<CR>", function()
    local context = require("neosapling.status.context")
    local item = context.get_item_at_cursor(line_map)
    if not item then return end
    if item.type == "commit" then
      require("neosapling.actions.stack").goto_commit(item.commit.node)
    elseif item.type == "bookmark" then
      require("neosapling.actions.stack").goto_commit(item.bookmark.node)
    end
  end, { buffer = bufnr, desc = "Goto commit or bookmark" })

  -- Ctrl-r: manual refresh
  vim.keymap.set("n", "<C-r>", function()
    require("neosapling.status").refresh()
  end, { buffer = bufnr, desc = "Refresh status" })

  -- p: pull from remote (lowercase to match Neogit convention)
  vim.keymap.set("n", "p", function()
    require("neosapling.actions.stack").pull()
  end, { buffer = bufnr, desc = "Pull from remote" })

  -- d: show side-by-side file diff or open diff popup for commit
  vim.keymap.set("n", "d", function()
    local context = require("neosapling.status.context")
    local item = context.get_item_at_cursor(line_map)
    if not item then return end
    if item.type == "file" then
      require("neosapling.diff.split").open_file_diff(item.file.path)
    elseif item.type == "commit" then
      require("neosapling.popups.diff").create(item.commit)
    end
  end, { buffer = bufnr, desc = "Show file diff or open diff popup" })
end

--- Setup folds for status buffer
---@param folds RenderFold[] Fold regions from renderer
local function setup_folds(folds)
  fold_regions = folds
  cache_valid = false -- Invalidate cache

  local win = vim.fn.bufwinid(status_buffer.handle)
  if win ~= -1 then
    vim.wo[win].foldmethod = "expr"
    vim.wo[win].foldexpr = "v:lua.neosapling_status_foldexpr(v:lnum)"
    vim.wo[win].foldlevel = 99 -- Start with all open
    vim.wo[win].foldenable = true
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

  -- Save cursor position before render
  local win = vim.fn.bufwinid(status_buffer.handle)
  local cursor = nil
  if win ~= -1 then
    cursor = vim.api.nvim_win_get_cursor(win)
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
  status_buffer:set_highlights(result.highlights)

  -- Setup folds
  setup_folds(result.folds)

  -- Close sections that should be collapsed by default (only on initial open)
  if is_initial_open then
    close_default_collapsed(result.folds)
    is_initial_open = false
  end

  -- Restore cursor position after render
  if cursor and win ~= -1 and vim.api.nvim_win_is_valid(win) then
    local line_count = vim.api.nvim_buf_line_count(status_buffer.handle)
    cursor[1] = math.min(cursor[1], line_count)
    vim.api.nvim_win_set_cursor(win, cursor)
  end
end

-- Version token for preventing stale data from async operations
local current_version = nil

--- Refresh status data and re-render
--- All three CLI calls (status, smartlog, bookmarks) execute in parallel.
--- A completion counter pattern collects results and renders when all finish.
function M.refresh()
  local version = vim.loop.now()
  current_version = version

  local results = {}
  local pending = 3 -- Number of parallel CLI calls

  local function on_complete()
    pending = pending - 1
    if pending > 0 then return end
    if current_version ~= version then return end -- Stale

    current_data = {
      status = results.status,
      commits = results.commits or {},
      bookmarks = results.bookmarks or {},
    }

    vim.schedule(function()
      M._render()
    end)
  end

  -- All three fire simultaneously
  neosapling.sl.status(function(grouped_status, err)
    if current_version ~= version then return end -- Stale
    if err then
      vim.notify("NeoSapling: " .. err, vim.log.levels.ERROR)
      return -- Error in primary data source aborts refresh
    end
    results.status = grouped_status
    on_complete()
  end)

  neosapling.sl.smartlog(function(commits, err)
    if current_version ~= version then return end -- Stale
    if err then commits = {} end -- Non-fatal: show status without smartlog
    results.commits = commits
    on_complete()
  end)

  neosapling.sl.bookmarks(function(bookmarks, err)
    if current_version ~= version then return end -- Stale
    if err then bookmarks = {} end -- Non-fatal: show status without bookmarks
    results.bookmarks = bookmarks
    on_complete()
  end)
end

--- Open the status buffer
function M.open()
  -- Create or get existing buffer
  if not status_buffer or not status_buffer:is_valid() then
    status_buffer = ui.Buffer:new("neosapling://status")
    setup_buffer()
  end

  status_buffer:show("tab")
  require("neosapling.lib.watcher").notify_open("status")
  is_initial_open = true
  M.refresh()
end

--- Close the status buffer
function M.close()
  require("neosapling.lib.watcher").notify_close("status")
  if status_buffer and status_buffer:is_valid() then
    -- Close all windows showing the status buffer
    local wins = vim.fn.win_findbuf(status_buffer.handle)

    if vim.fn.tabpagenr('$') > 1 then
      -- We have multiple tabs, close the status tab
      for _, win in ipairs(wins) do
        if vim.api.nvim_win_is_valid(win) then
          local tab = vim.api.nvim_win_get_tabpage(win)
          pcall(vim.api.nvim_set_current_tabpage, tab)
          pcall(vim.cmd, "tabclose")
        end
      end
    else
      -- Only one tab - switch to previous buffer
      local ok = pcall(vim.cmd, "bprevious")
      if not ok or vim.api.nvim_get_current_buf() == status_buffer.handle then
        vim.cmd("enew")
      end
    end

    status_buffer:destroy()
    status_buffer = nil
  end
  current_data = nil
  line_map = {}
  fold_regions = {}
  expanded_files = {}
  cache_valid = false
  is_initial_open = false
end

--- Get the current line map (for context module)
---@return table<number, Item>
function M.get_line_map()
  return line_map
end

return M
