--- Buffer-based commit message editor.
--- Opens a buffer for commit/amend message, executes commit/amend on save.
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

--- Get the current commit message for amend
---@param callback fun(message: string|nil, err: string|nil)
local function get_current_commit_message(callback)
  cli.log():opt("-r", "."):template("{desc}"):call({}, function(result)
    if result.code == 0 then
      local msg = table.concat(result.stdout, "\n")
      callback(msg, nil)
    else
      callback(nil, table.concat(result.stderr, "\n"))
    end
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

        -- Re-show status buffer (opens/shows AND refreshes data)
        local ok, status = pcall(require, "neosapling.status")
        if ok and status.open then
          status.open()  -- Opens/shows buffer AND refreshes data
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

--- Execute amend with message from buffer
---@param buf table Amend buffer
local function execute_amend(buf)
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
    vim.notify("Empty commit message - amend aborted", vim.log.levels.ERROR)
    vim.bo[buf.handle].modified = false
    return
  end

  -- Write message to temp file and amend
  local tmpfile = vim.fn.tempname()
  vim.fn.writefile(vim.split(message, "\n"), tmpfile)

  cli.amend():opt("-l", tmpfile):call({}, function(result)
    vim.fn.delete(tmpfile)

    vim.schedule(function()
      if result.code == 0 then
        -- Close amend buffer
        buf:destroy()
        active_commit_buf = nil

        -- Refresh status and smartlog views
        local ok, status = pcall(require, "neosapling.status")
        if ok and status.open then
          status.open()
        end
        local ok2, smartlog = pcall(require, "neosapling.smartlog")
        if ok2 and smartlog.refresh then
          smartlog.refresh()
        end

        vim.notify("Commit amended", vim.log.levels.INFO)
      else
        local err_msg = table.concat(result.stderr or {}, "\n")
        if err_msg == "" then
          err_msg = "Unknown error"
        end
        vim.notify("Amend failed: " .. err_msg, vim.log.levels.ERROR)
      end
    end)
  end)

  -- Mark buffer as not modified to prevent "unsaved" warning
  vim.bo[buf.handle].modified = false
end

--- Set up the editor buffer with content and keymaps
---@param opts table Options (amend boolean)
---@param files string[] Files for comment section
---@param existing_message string|nil Existing commit message for amend
local function setup_editor_buffer(opts, files, existing_message)
  local is_amend = opts.amend == true
  local buf_name = is_amend and "neosapling://amend" or "neosapling://commit"

  -- Create buffer
  local buf = ui.Buffer:new(buf_name)
  active_commit_buf = buf

  -- Set buffer options for editing
  vim.bo[buf.handle].buftype = "acwrite"
  vim.bo[buf.handle].filetype = "gitcommit"
  vim.bo[buf.handle].modifiable = true

  -- Build initial content
  local initial_lines = {}

  if is_amend and existing_message then
    -- Pre-fill with existing commit message
    for _, line in ipairs(vim.split(existing_message, "\n")) do
      table.insert(initial_lines, line)
    end
  else
    -- Empty first line for new commit
    table.insert(initial_lines, "")
  end

  -- Add comment lines
  local comment_action = is_amend and "Amend commit message above." or "Enter commit message above."
  table.insert(initial_lines, "# " .. comment_action)
  table.insert(initial_lines, "# Lines starting with # will be ignored.")
  table.insert(initial_lines, "#")

  if #files > 0 then
    table.insert(initial_lines, "# Files to be committed:")
    for _, file in ipairs(files) do
      table.insert(initial_lines, "#   " .. file)
    end
  end

  vim.api.nvim_buf_set_lines(buf.handle, 0, -1, false, initial_lines)
  vim.bo[buf.handle].modified = false

  -- Show in split
  buf:show("split")

  -- Position cursor at first line
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  -- Start in insert mode for new commit, normal mode for amend (message already present)
  if not is_amend then
    vim.cmd("startinsert")
  end

  -- Setup BufWriteCmd to execute on save
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf.handle,
    callback = function()
      if is_amend then
        execute_amend(buf)
      else
        execute_commit(buf, files)
      end
    end,
  })

  -- Setup close handlers
  vim.keymap.set("n", "q", function()
    buf:destroy()
    active_commit_buf = nil
  end, { buffer = buf.handle, desc = "Close " .. (is_amend and "amend" or "commit") .. " buffer" })

  -- Cleanup on buffer wipeout
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf.handle,
    callback = function()
      active_commit_buf = nil
    end,
  })
end

--- Open commit/amend editor buffer
---@param opts? {amend?: boolean}
function M.open(opts)
  opts = opts or {}

  -- Prevent multiple commit/amend buffers
  if active_commit_buf and active_commit_buf:is_valid() then
    vim.notify("Commit buffer already open", vim.log.levels.WARN)
    return
  end

  if opts.amend then
    -- Amend flow: fetch current message, then open editor with it
    get_current_commit_message(function(existing_msg, err)
      if err then
        vim.schedule(function()
          vim.notify("Failed to get commit message: " .. err, vim.log.levels.ERROR)
        end)
        return
      end

      -- Also get files for the comment section (not gated on has_files)
      get_commit_files(function(files, _has_files)
        vim.schedule(function()
          setup_editor_buffer(opts, files, existing_msg)
        end)
      end)
    end)
  else
    -- Commit flow: get files first, gate on has_files
    get_commit_files(function(files, has_files)
      vim.schedule(function()
        if not has_files then
          vim.notify("Nothing staged to commit", vim.log.levels.WARN)
          return
        end

        setup_editor_buffer(opts, files, nil)
      end)
    end)
  end
end

return M
