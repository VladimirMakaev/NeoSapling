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
local diff_buffer = nil
local prev_bufnr = nil

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

  -- d opens diff popup
  vim.keymap.set("n", "d", function()
    local lnum = vim.fn.line(".")
    local item = line_map[lnum]
    if item and item.type == "commit" then
      require("neosapling.popups.diff").create(item.commit)
    else
      vim.notify("No commit under cursor", vim.log.levels.INFO)
    end
  end, { buffer = bufnr, desc = "Open diff popup" })

  -- Enter: goto commit under cursor
  vim.keymap.set("n", "<CR>", function()
    local item = line_map[vim.fn.line(".")]
    if item and item.type == "commit" then
      require("neosapling.actions.stack").goto_commit(item.commit.node)
    end
  end, { buffer = bufnr, desc = "Goto commit" })

  -- H: hide commit with confirmation
  vim.keymap.set("n", "H", function()
    local item = line_map[vim.fn.line(".")]
    if not item or item.type ~= "commit" then return end
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

  -- P: pull from remote
  vim.keymap.set("n", "P", function()
    require("neosapling.actions.stack").pull()
  end, { buffer = bufnr, desc = "Pull from remote" })

  -- c: open commit popup
  vim.keymap.set("n", "c", function()
    require("neosapling.popups.commit").create()
  end, { buffer = bufnr, desc = "Open commit popup" })

  -- G: graft commit with confirmation
  vim.keymap.set("n", "G", function()
    local item = line_map[vim.fn.line(".")]
    if not item or item.type ~= "commit" then return end
    local node = item.commit.node
    local choice = vim.fn.confirm("Graft commit " .. node:sub(1, 7) .. " to current location?", "&Yes\n&No", 2)
    if choice == 1 then
      require("neosapling.actions.stack").graft(node)
    end
  end, { buffer = bufnr, desc = "Graft commit" })

  -- U: unhide commit
  vim.keymap.set("n", "U", function()
    local item = line_map[vim.fn.line(".")]
    if not item or item.type ~= "commit" then return end
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
  -- Save the current buffer so we can restore it on close
  prev_bufnr = vim.api.nvim_get_current_buf()

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
    -- Restore the buffer the user had before opening smartlog
    if prev_bufnr and vim.api.nvim_buf_is_valid(prev_bufnr) then
      vim.api.nvim_set_current_buf(prev_bufnr)
    else
      -- Fallback: create a fresh empty buffer
      vim.cmd("enew")
    end
    smartlog_buffer:destroy()
    smartlog_buffer = nil
  end
  prev_bufnr = nil
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

  -- q closes diff buffer
  vim.keymap.set("n", "q", function()
    if diff_buffer and diff_buffer:is_valid() then
      diff_buffer:destroy()
      diff_buffer = nil
    end
  end, { buffer = bufnr, desc = "Close diff buffer" })
end

--- Display diff in a split buffer
---@param diffs FileDiff[] Parsed diff data
---@param commit CommitExtended The commit being diffed
---@param diff_type string Description of diff type (e.g., "vs parent", "vs working copy")
function M._show_diff_buffer(diffs, commit, diff_type)
  -- Clean up previous diff buffer (Pitfall #5)
  if diff_buffer and diff_buffer:is_valid() then
    diff_buffer:destroy()
  end

  diff_buffer = ui.Buffer:new("neosapling://diff/" .. commit.node:sub(1, 7))

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
  table.insert(lines, commit.desc)
  line_num = line_num + 1
  table.insert(lines, "")
  line_num = line_num + 1

  if #diffs == 0 then
    table.insert(lines, "No changes")
    diff_buffer:set_lines(lines)
    diff_buffer:show("split")
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
  for _, hl in ipairs(highlights) do
    diff_buffer:add_highlight(hl.line, hl.col_start, hl.col_end, hl.hl)
  end

  -- Show in split
  diff_buffer:show("split")

  -- Set filetype for syntax
  vim.bo[diff_buffer.handle].filetype = "diff"

  M._setup_diff_buffer_keymaps()
end

return M
