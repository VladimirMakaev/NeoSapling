--- Buffer-based commit message editor.
--- Opens a buffer for commit message, executes commit on save.
--- @module neosapling.commit.editor

local ui = require("neosapling.lib.ui")
local cli = require("neosapling.lib.cli")
local staged = require("neosapling.status.staged")

local M = {}

-- Track active commit buffer to prevent duplicates
local active_commit_buf = nil

--- Get files to commit (added + virtually staged modified)
---@param callback fun(files: string[], has_files: boolean)
local function get_commit_files(callback)
  local neosapling = require("neosapling")

  neosapling.sl.status(function(grouped, err)
    if err then
      callback({}, false)
      return
    end

    local files = {}

    -- Added files (A) are always included
    for _, file in ipairs(grouped.added or {}) do
      table.insert(files, file.path)
    end

    -- Virtually staged modified files
    local staged_modified = staged.get_staged()
    for _, path in ipairs(staged_modified) do
      table.insert(files, path)
    end

    callback(files, #files > 0)
  end)
end

--- Execute commit with message from buffer
---@param buf table Commit buffer
---@param files string[] Files to commit
local function execute_commit(buf, files)
  -- Get message from buffer, filter comment lines
  local lines = buf:get_lines()
  local message_lines = {}
  for _, line in ipairs(lines) do
    if not line:match("^#") then
      table.insert(message_lines, line)
    end
  end

  -- Trim whitespace
  local message = table.concat(message_lines, "\n")
  message = message:gsub("^%s+", ""):gsub("%s+$", "")

  if message == "" then
    vim.notify("Empty commit message - commit aborted", vim.log.levels.ERROR)
    vim.bo[buf.handle].modified = false
    return
  end

  -- For multi-line messages, use temp file (Pitfall #6 from research)
  local tmpfile = vim.fn.tempname()
  vim.fn.writefile(vim.split(message, "\n"), tmpfile)

  -- Build commit command
  local builder = cli.commit():opt("-l", tmpfile)

  -- Add files
  if #files > 0 then
    builder:files(files)
  end

  builder:call({}, function(result)
    -- Clean up temp file
    vim.fn.delete(tmpfile)

    vim.schedule(function()
      if result.code == 0 then
        -- Clear staged files
        staged.clear()

        -- Close commit buffer
        buf:destroy()
        active_commit_buf = nil

        -- Refresh status
        local ok, status = pcall(require, "neosapling.status")
        if ok and status.refresh then
          status.refresh()
        end

        vim.notify("Commit created", vim.log.levels.INFO)
      else
        local err_msg = table.concat(result.stderr or {}, "\n")
        if err_msg == "" then
          err_msg = "Unknown error"
        end
        vim.notify("Commit failed: " .. err_msg, vim.log.levels.ERROR)
      end
    end)
  end)

  -- Mark buffer as not modified to prevent "unsaved" warning
  vim.bo[buf.handle].modified = false
end

--- Open commit editor buffer
---@param opts? {amend?: boolean}
function M.open(opts)
  opts = opts or {}

  -- Prevent multiple commit buffers
  if active_commit_buf and active_commit_buf:is_valid() then
    vim.notify("Commit buffer already open", vim.log.levels.WARN)
    return
  end

  -- Get files to commit
  get_commit_files(function(files, has_files)
    vim.schedule(function()
      if not has_files and not opts.amend then
        vim.notify("Nothing staged to commit", vim.log.levels.WARN)
        return
      end

      -- Create commit buffer
      local buf = ui.Buffer:new("neosapling://commit")
      active_commit_buf = buf

      -- Set buffer options for commit editing
      vim.bo[buf.handle].buftype = "acwrite" -- Allow write with autocmd
      vim.bo[buf.handle].filetype = "gitcommit" -- Syntax highlighting
      vim.bo[buf.handle].modifiable = true

      -- Set initial content
      local initial_lines = {
        "",
        "# Enter commit message above.",
        "# Lines starting with # will be ignored.",
        "#",
        "# Files to be committed:",
      }
      for _, file in ipairs(files) do
        table.insert(initial_lines, "#   " .. file)
      end

      vim.api.nvim_buf_set_lines(buf.handle, 0, -1, false, initial_lines)
      vim.bo[buf.handle].modified = false -- Start clean

      -- Show in split
      buf:show("split")

      -- Position cursor at first line
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      -- Start in insert mode
      vim.cmd("startinsert")

      -- Setup BufWriteCmd to execute commit on save
      vim.api.nvim_create_autocmd("BufWriteCmd", {
        buffer = buf.handle,
        callback = function()
          execute_commit(buf, files)
        end,
      })

      -- Setup close handlers
      vim.keymap.set("n", "q", function()
        buf:destroy()
        active_commit_buf = nil
      end, { buffer = buf.handle, desc = "Close commit buffer" })

      -- Cleanup on buffer leave
      vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = buf.handle,
        callback = function()
          active_commit_buf = nil
        end,
      })
    end)
  end)
end

return M
