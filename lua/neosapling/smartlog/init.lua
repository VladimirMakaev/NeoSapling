--- Smartlog buffer module for NeoSapling.
--- Orchestrates buffer lifecycle, data fetch, render, and keymap management.
--- Phase 8.1: Rewritten to render ssl output directly with cursor positioning
--- and commit-jumping navigation.
--- @module neosapling.smartlog

local Buffer = require("neosapling.lib.ui.buffer")
local neosapling = require("neosapling")
local components = require("neosapling.smartlog.components")
local hintbar = require("neosapling.lib.ui.hintbar")

local M = {}

-- Module state
local smartlog_buffer = nil
local current_data = nil
local line_map = {}
local diff_buffer = nil

-- Version token for preventing stale data from async operations
local current_version = nil

-- Flag for initial open cursor positioning (07-06 pattern)
local is_initial_open = false

--- Find the byte column of the hash in a commit line
---@param lnum number 1-indexed line number
---@return number col 0-indexed byte column of hash (or 0 if not found)
local function find_hash_col(lnum)
  if not smartlog_buffer or not smartlog_buffer:is_valid() then return 0 end
  local lines = vim.api.nvim_buf_get_lines(smartlog_buffer.handle, lnum - 1, lnum, false)
  if #lines == 0 then return 0 end
  local item = line_map[lnum]
  if item and item.commit and item.commit.node then
    local start = lines[1]:find(item.commit.node, 1, true)
    if start then return start - 1 end
  end
  return 0
end

--- Internal: Position cursor at the current (@) commit
local function position_at_current_commit()
  if not smartlog_buffer or not smartlog_buffer:is_valid() then return end
  local wins = vim.fn.win_findbuf(smartlog_buffer.handle)
  if #wins == 0 then return end

  -- Look for @ (working copy) commit
  for lnum, item in pairs(line_map) do
    if item.type == "commit" and item.commit.graphnode == "@" then
      local col = find_hash_col(lnum)
      for _, win in ipairs(wins) do
        if vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_win_set_cursor, win, { lnum, col })
        end
      end
      return
    end
  end

  -- Fallback: look for commit with local_changes = true
  for lnum, item in pairs(line_map) do
    if item.type == "commit" and item.commit.local_changes then
      local col = find_hash_col(lnum)
      for _, win in ipairs(wins) do
        if vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_win_set_cursor, win, { lnum, col })
        end
      end
      return
    end
  end
end

-- Expose for testability
M._position_at_current_commit = position_at_current_commit

--- Setup buffer options and keymaps
local function setup_buffer()
  if not smartlog_buffer or not smartlog_buffer:is_valid() then
    return
  end

  local bufnr = smartlog_buffer.handle

  -- Set filetype
  vim.bo[bufnr].filetype = "neosapling"

  -- q closes smartlog and returns to previous buffer
  vim.keymap.set("n", "q", function()
    M.close()
  end, { buffer = bufnr, desc = "Close smartlog" })

  -- ? opens help popup
  vim.keymap.set("n", "?", function()
    require("neosapling.popups.help").create()
  end, { buffer = bufnr, desc = "Open help popup" })

  -- d opens diff popup — works on commit AND message lines
  vim.keymap.set("n", "d", function()
    local lnum = vim.fn.line(".")
    local item = line_map[lnum]
    if item and (item.type == "commit" or item.type == "message") then
      require("neosapling.popups.diff").create(item.commit)
    else
      vim.notify("No commit under cursor", vim.log.levels.INFO)
    end
  end, { buffer = bufnr, desc = "Open diff popup" })

  -- Enter: goto commit under cursor — works on commit AND message lines
  vim.keymap.set("n", "<CR>", function()
    local item = line_map[vim.fn.line(".")]
    if item and (item.type == "commit" or item.type == "message") then
      require("neosapling.actions.stack").goto_commit(item.commit.node)
    end
  end, { buffer = bufnr, desc = "Goto commit" })

  -- J: jump to next commit line (cursor on hash)
  vim.keymap.set("n", "J", function()
    local lnum = vim.fn.line(".")
    local total = vim.fn.line("$")
    local target = lnum + 1
    while target <= total do
      local item = line_map[target]
      if item and item.type == "commit" then
        local col = find_hash_col(target)
        vim.api.nvim_win_set_cursor(0, { target, col })
        return
      end
      target = target + 1
    end
  end, { buffer = bufnr, desc = "Jump to next commit" })

  -- K: jump to previous commit line (cursor on hash)
  vim.keymap.set("n", "K", function()
    local lnum = vim.fn.line(".")
    local target = lnum - 1
    while target >= 1 do
      local item = line_map[target]
      if item and item.type == "commit" then
        local col = find_hash_col(target)
        vim.api.nvim_win_set_cursor(0, { target, col })
        return
      end
      target = target - 1
    end
  end, { buffer = bufnr, desc = "Jump to previous commit" })

  -- H: hide commit with confirmation — works on commit AND message lines
  vim.keymap.set("n", "H", function()
    local item = line_map[vim.fn.line(".")]
    if not item or (item.type ~= "commit" and item.type ~= "message") then return end
    local node = item.commit.node
    local prompt
    if item.commit.graphnode == "@" then
      prompt = "Hide current commit? This will checkout parent."
    else
      prompt = "Hide commit " .. node:sub(1, 7) .. "?"
    end
    local choice = vim.fn.confirm(prompt, "&Yes\n&No", 2)
    if choice == 1 then
      require("neosapling.actions.stack").hide(node)
    end
  end, { buffer = bufnr, desc = "Hide commit" })

  -- Ctrl-r: manual refresh
  vim.keymap.set("n", "<C-r>", function()
    require("neosapling.smartlog").refresh()
  end, { buffer = bufnr, desc = "Refresh smartlog" })

  -- p: pull from remote (lowercase to match Neogit convention)
  vim.keymap.set("n", "p", function()
    require("neosapling.actions.stack").pull()
  end, { buffer = bufnr, desc = "Pull from remote" })

  -- c: open commit popup
  vim.keymap.set("n", "c", function()
    require("neosapling.popups.commit").create()
  end, { buffer = bufnr, desc = "Open commit popup" })

  -- G: graft commit with confirmation — works on commit AND message lines
  vim.keymap.set("n", "G", function()
    local item = line_map[vim.fn.line(".")]
    if not item or (item.type ~= "commit" and item.type ~= "message") then return end
    local node = item.commit.node
    local choice = vim.fn.confirm("Graft commit " .. node:sub(1, 7) .. " to current location?", "&Yes\n&No", 2)
    if choice == 1 then
      require("neosapling.actions.stack").graft(node)
    end
  end, { buffer = bufnr, desc = "Graft commit" })

  -- U: unhide commit — works on commit AND message lines
  vim.keymap.set("n", "U", function()
    local item = line_map[vim.fn.line(".")]
    if not item or (item.type ~= "commit" and item.type ~= "message") then return end
    require("neosapling.actions.stack").unhide(item.commit.node)
  end, { buffer = bufnr, desc = "Unhide commit" })

  -- r: rebase with destination prompt
  vim.keymap.set("n", "r", function()
    vim.ui.input({ prompt = "Rebase destination: " }, function(dest)
      if dest and dest ~= "" then
        require("neosapling.actions.stack").rebase(dest)
      end
    end)
  end, { buffer = bufnr, desc = "Rebase" })
end

--- Internal: Render current data to buffer
function M._render()
  if not current_data or not smartlog_buffer or not smartlog_buffer:is_valid() then
    return
  end

  -- Save cursor position before render (cursor save/restore pattern from 07-06)
  local cursor_pos = nil
  local wins = vim.fn.win_findbuf(smartlog_buffer.handle)
  if #wins > 0 and vim.api.nvim_win_is_valid(wins[1]) then
    cursor_pos = vim.api.nvim_win_get_cursor(wins[1])
  end

  local lines, highlights, new_line_map = components.build(current_data)

  -- Prepend hint bar (line 1) + blank line (line 2) before smartlog content
  local smartlog_hints = {
    { key = "?", action = "Help" },
    { key = "c", action = "Commit" },
    { key = "d", action = "Diff" },
    { key = "J", action = "Next" },
    { key = "K", action = "Prev" },
    { key = "p", action = "Pull" },
    { key = "q", action = "Close" },
  }
  local hint_line, hint_hls = hintbar.build(smartlog_hints, 0)
  table.insert(lines, 1, hint_line)
  table.insert(lines, 2, "")

  -- Offset ALL existing highlights by +2 for the 2 prepended lines
  for _, hl in ipairs(highlights) do
    hl.line = hl.line + 2
  end

  -- Offset ALL line_map keys by +2
  local offset_map = {}
  for k, v in pairs(new_line_map) do
    offset_map[k + 2] = v
  end

  -- Add hint bar highlights
  for _, hl in ipairs(hint_hls) do
    table.insert(highlights, hl)
  end

  line_map = offset_map

  smartlog_buffer:set_lines(lines)
  smartlog_buffer:clear_highlights()
  smartlog_buffer:set_highlights(highlights)

  -- Restore cursor or position at @ commit
  if cursor_pos and not is_initial_open then
    -- Restore previous position (clamped to buffer bounds)
    local max_line = #lines
    local restore_line = math.min(cursor_pos[1], max_line)
    for _, win in ipairs(wins) do
      if vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_set_cursor, win, { restore_line, cursor_pos[2] })
      end
    end
  else
    -- Initial open: position at @ commit
    position_at_current_commit()
    is_initial_open = false
  end
end

--- Refresh smartlog data and re-render
function M.refresh()
  local version = vim.loop.now()
  current_version = version

  neosapling.sl.smartlog_ssl(function(ssl_lines, err)
    if current_version ~= version then return end -- Stale
    if err then
      vim.notify("NeoSapling: " .. err, vim.log.levels.ERROR)
      return
    end

    current_data = ssl_lines  -- Raw lines, not wrapped in {commits: ...}

    vim.schedule(function()
      M._render()
    end)
  end)
end

--- Open the smartlog buffer (full-screen in new tab)
function M.open()
  -- Create or get existing buffer
  if not smartlog_buffer or not smartlog_buffer:is_valid() then
    smartlog_buffer = Buffer:new("neosapling://smartlog")
    setup_buffer()
  end

  -- Mark as initial open for cursor positioning
  is_initial_open = true

  -- Show in a new tab (full screen, like Neogit)
  smartlog_buffer:show("tab")
  require("neosapling.lib.watcher").notify_open("smartlog")
  M.refresh()
end

--- Close the smartlog buffer
function M.close()
  require("neosapling.lib.watcher").notify_close("smartlog")
  if smartlog_buffer and smartlog_buffer:is_valid() then
    -- Close all windows showing the smartlog buffer
    local wins = vim.fn.win_findbuf(smartlog_buffer.handle)

    if vim.fn.tabpagenr('$') > 1 then
      -- We have multiple tabs, close the smartlog tab
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
      if not ok or vim.api.nvim_get_current_buf() == smartlog_buffer.handle then
        vim.cmd("enew")
      end
    end

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

--- Setup keymaps for diff buffer
function M._setup_diff_buffer_keymaps()
  if not diff_buffer or not diff_buffer:is_valid() then
    return
  end

  local bufnr = diff_buffer.handle

  -- q closes diff tab and returns to previous tab
  vim.keymap.set("n", "q", function()
    if diff_buffer and diff_buffer:is_valid() then
      local wins = vim.fn.win_findbuf(diff_buffer.handle)
      diff_buffer:destroy()
      diff_buffer = nil

      -- Close the diff tab if we have multiple tabs
      if vim.fn.tabpagenr('$') > 1 then
        for _, win in ipairs(wins) do
          if vim.api.nvim_win_is_valid(win) then
            local tab = vim.api.nvim_win_get_tabpage(win)
            pcall(vim.api.nvim_set_current_tabpage, tab)
            pcall(vim.cmd, "tabclose")
          end
        end
      end
    end
  end, { buffer = bufnr, desc = "Close diff buffer" })
end

--- Display diff in a split buffer
---@param diffs FileDiff[] Parsed diff data
---@param commit SslCommit|CommitExtended The commit being diffed
---@param diff_type string Description of diff type (e.g., "vs parent", "vs working copy")
function M._show_diff_buffer(diffs, commit, diff_type)
  -- Clean up previous diff buffer (Pitfall #5)
  if diff_buffer and diff_buffer:is_valid() then
    diff_buffer:destroy()
  end

  diff_buffer = Buffer:new("neosapling://diff/" .. commit.node:sub(1, 7))

  local lines = {}
  local highlights = {}
  local line_num = 0

  -- Header
  table.insert(lines, "Diff for " .. commit.node:sub(1, 7) .. " " .. diff_type)
  table.insert(highlights, {
    line = line_num,
    col_start = 0,
    col_end = #lines[1],
    hl = "NeoSaplingHeader",
  })
  line_num = line_num + 1
  table.insert(lines, commit.desc or "")
  line_num = line_num + 1
  table.insert(lines, "")
  line_num = line_num + 1

  if #diffs == 0 then
    table.insert(lines, "No changes")
    diff_buffer:set_lines(lines)
    diff_buffer:clear_highlights()
    diff_buffer:set_highlights(highlights)
    diff_buffer:show("tab")
    M._setup_diff_buffer_keymaps()
    return
  end

  for _, file_diff in ipairs(diffs) do
    -- File header
    local from_line = "--- " .. (file_diff.from_path or "/dev/null")
    table.insert(lines, from_line)
    table.insert(highlights, {
      line = line_num,
      col_start = 0,
      col_end = #from_line,
      hl = "NeoSaplingHash",
    })
    line_num = line_num + 1

    local to_line = "+++ " .. (file_diff.to_path or "/dev/null")
    table.insert(lines, to_line)
    table.insert(highlights, {
      line = line_num,
      col_start = 0,
      col_end = #to_line,
      hl = "NeoSaplingHash",
    })
    line_num = line_num + 1

    for _, hunk in ipairs(file_diff.hunks or {}) do
      -- Hunk header
      local hunk_header = string.format(
        "@@ -%d,%d +%d,%d @@%s",
        hunk.old_start or 0, hunk.old_count or 0,
        hunk.new_start or 0, hunk.new_count or 0,
        hunk.header and (" " .. hunk.header) or ""
      )
      table.insert(lines, hunk_header)
      table.insert(highlights, {
        line = line_num,
        col_start = 0,
        col_end = #hunk_header,
        hl = "NeoSaplingSection",
      })
      line_num = line_num + 1

      -- Diff lines
      for _, diff_line in ipairs(hunk.lines or {}) do
        table.insert(lines, diff_line)
        local hl = nil
        if diff_line:sub(1, 1) == "+" then
          hl = "DiffAdd"
        elseif diff_line:sub(1, 1) == "-" then
          hl = "DiffDelete"
        end
        if hl then
          table.insert(highlights, {
            line = line_num,
            col_start = 0,
            col_end = #diff_line,
            hl = hl,
          })
        end
        line_num = line_num + 1
      end
    end

    table.insert(lines, "")
    line_num = line_num + 1
  end

  diff_buffer:set_lines(lines)
  diff_buffer:clear_highlights()
  diff_buffer:set_highlights(highlights)

  -- Show full screen in new tab (matches smartlog/status pattern)
  diff_buffer:show("tab")

  -- Set filetype for syntax
  vim.bo[diff_buffer.handle].filetype = "diff"

  M._setup_diff_buffer_keymaps()
end

return M
