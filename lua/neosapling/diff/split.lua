--- Diff split module for NeoSapling.
--- Provides side-by-side diff viewing with diffview.nvim as primary
--- and built-in :diffthis as fallback.
--- @module neosapling.diff.split

local M = {}

-- Cached diffview.nvim availability (nil = not checked yet)
local diffview_available = nil

--- Check if diffview.nvim is installed and available.
--- Result is cached after first check.
---@return boolean
function M.has_diffview()
  if diffview_available == nil then
    local ok = pcall(require, "diffview")
    diffview_available = ok
  end
  return diffview_available
end

--- Reset the diffview cache (useful for testing).
function M._reset_cache()
  diffview_available = nil
end

-- State for built-in diff cleanup
local diff_state = nil

--- Clean up the built-in :diffthis diff view.
--- Closes the scratch buffer, runs :diffoff on the original, and restores window.
local function cleanup_builtin_diff()
  if not diff_state then return end

  local state = diff_state
  diff_state = nil

  -- Close the scratch buffer window if it still exists
  if state.scratch_win and vim.api.nvim_win_is_valid(state.scratch_win) then
    vim.api.nvim_win_close(state.scratch_win, true)
  end

  -- Delete the scratch buffer
  if state.scratch_buf and vim.api.nvim_buf_is_valid(state.scratch_buf) then
    vim.api.nvim_buf_delete(state.scratch_buf, { force = true })
  end

  -- Turn off diff mode on the original buffer window
  if state.orig_win and vim.api.nvim_win_is_valid(state.orig_win) then
    vim.api.nvim_win_call(state.orig_win, function()
      vim.cmd("diffoff")
    end)
    -- Restore focus to original window
    vim.api.nvim_set_current_win(state.orig_win)
  end
end

--- Open a side-by-side diff for a working copy file vs its committed version.
--- Uses diffview.nvim when available, falls back to :diffthis.
---
--- Layout: working copy on the LEFT, committed version on the RIGHT.
---@param filepath string Path to the file (relative to repo root)
function M.open_file_diff(filepath)
  -- Try diffview.nvim first
  if M.has_diffview() then
    local ok, err = pcall(function()
      vim.cmd("DiffviewOpen -- " .. vim.fn.fnameescape(filepath))
    end)
    if ok then
      return
    end
    -- diffview.nvim failed (likely no Hg/Sapling adapter configured)
    -- Clean up any partial diffview state before falling back
    pcall(vim.cmd, "DiffviewClose")
    -- Fall through to built-in
    vim.notify(
      "diffview.nvim failed, using built-in diff: " .. tostring(err),
      vim.log.levels.DEBUG
    )
  end

  -- Built-in :diffthis fallback
  M._open_builtin_file_diff(filepath)
end

--- Built-in :diffthis fallback for file diff.
--- Opens working copy on LEFT, committed version on RIGHT.
---@param filepath string Path to the file (relative to repo root)
function M._open_builtin_file_diff(filepath)
  -- Clean up any previous diff state
  cleanup_builtin_diff()

  -- Save current window for later restoration
  local orig_win = vim.api.nvim_get_current_win()

  -- Open the working copy file in the current window (LEFT side)
  -- Wrap in pcall: BufRead/BufEnter autocommands from git-only plugins
  -- (gitsigns, fugitive, vim-signify) may fail in a pure Sapling repo
  local edit_ok, edit_err = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(filepath))
  if not edit_ok then
    vim.notify(
      "Failed to open file for diff: " .. tostring(edit_err),
      vim.log.levels.WARN
    )
    return
  end
  -- diffthis may fail if VCS-aware plugins interfere; continue without diff mode
  local dt_ok, dt_err = pcall(vim.cmd, "diffthis")
  if not dt_ok then
    vim.notify(
      "diffthis failed on working copy: " .. tostring(dt_err),
      vim.log.levels.DEBUG
    )
  end

  -- Open a vertical split on the RIGHT for committed version
  vim.cmd("vsplit")
  local scratch_win = vim.api.nvim_get_current_win()

  -- Create scratch buffer for committed content
  local scratch_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(scratch_buf)

  -- Configure scratch buffer
  vim.bo[scratch_buf].buftype = "nofile"
  vim.bo[scratch_buf].bufhidden = "wipe"
  vim.bo[scratch_buf].swapfile = false

  -- Detect filetype for syntax highlighting
  local ft = vim.filetype.match({ filename = filepath }) or ""
  vim.bo[scratch_buf].filetype = ft

  -- Set a descriptive buffer name
  local buf_name = "neosapling://committed/" .. filepath
  pcall(vim.api.nvim_buf_set_name, scratch_buf, buf_name)

  -- Save diff state for cleanup
  diff_state = {
    orig_win = orig_win,
    scratch_win = scratch_win,
    scratch_buf = scratch_buf,
  }

  -- Fetch committed content via sl cat
  local cli = require("neosapling.lib.cli")
  cli.builder():arg("cat"):opt("-r", "."):arg(filepath):call({}, function(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(scratch_buf) then return end

      -- result.stdout is string[] (lines from runner)
      local lines = result.stdout or {}

      -- Remove trailing empty string from accumulator if present
      if #lines > 0 and lines[#lines] == "" then
        table.remove(lines, #lines)
      end

      vim.bo[scratch_buf].modifiable = true
      vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, lines)
      vim.bo[scratch_buf].modifiable = false

      -- Enable diff mode on the scratch buffer
      if vim.api.nvim_win_is_valid(scratch_win) then
        vim.api.nvim_win_call(scratch_win, function()
          local dt_ok, dt_err = pcall(vim.cmd, "diffthis")
          if not dt_ok then
            vim.notify(
              "diffthis failed on scratch buffer: " .. tostring(dt_err),
              vim.log.levels.DEBUG
            )
          end
        end)
      end
    end)
  end)

  -- Set up q keymap on both buffers to close the diff view
  local function close_diff()
    cleanup_builtin_diff()
  end

  -- q on the working copy buffer
  local orig_buf = vim.api.nvim_win_get_buf(orig_win)
  vim.keymap.set("n", "q", close_diff, {
    buffer = orig_buf,
    desc = "Close diff view",
    nowait = true,
  })

  -- q on the scratch buffer
  vim.keymap.set("n", "q", close_diff, {
    buffer = scratch_buf,
    desc = "Close diff view",
    nowait = true,
  })
end

--- Open a diff view for a commit (vs parent or vs working copy).
--- Uses diffview.nvim when available, falls back to existing unified diff display.
---@param commit_node string The commit hash/node identifier
---@param diff_type string Either "parent" or "working"
function M.open_commit_diff(commit_node, diff_type)
  -- Try diffview.nvim first
  if M.has_diffview() then
    local ok, err = pcall(function()
      if diff_type == "parent" then
        -- Show changes introduced by this commit
        vim.cmd("DiffviewOpen " .. commit_node .. "^.." .. commit_node)
      elseif diff_type == "working" then
        -- Show what has changed since that commit (vs working copy)
        vim.cmd("DiffviewOpen " .. commit_node)
      end
    end)
    if ok then
      return
    end
    -- diffview.nvim failed, fall through
    -- Clean up any partial diffview state
    pcall(vim.cmd, "DiffviewClose")
    vim.notify(
      "diffview.nvim failed, using built-in diff: " .. tostring(err),
      vim.log.levels.DEBUG
    )
  end

  -- Built-in fallback: delegate to smartlog._show_diff_buffer
  -- which already handles unified diff display in a split.
  -- This is called from the diff popup, which passes the commit object.
  -- Return false to indicate fallback should be used by caller.
  return false
end

return M
