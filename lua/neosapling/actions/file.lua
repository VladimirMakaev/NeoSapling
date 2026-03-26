--- File action handlers for NeoSapling.
--- Implements stage, unstage, and discard operations.
--- @module neosapling.actions.file

local cli = require("neosapling.lib.cli")
local staged = require("neosapling.status.staged")
local watcher = require("neosapling.lib.watcher")

local M = {}

--- Schedule status buffer refresh
local function schedule_refresh()
  vim.schedule(function()
    local ok, status = pcall(require, "neosapling.status")
    if ok and status.refresh then
      status.refresh()
    end
  end)
end

--- Stage a file based on its current status
---@param file FileStatus The file to stage
---@param callback? function Called after operation
function M.stage(file, callback)
  callback = callback or function() end

  if file.status == "?" then
    -- Untracked: sl add
    cli.add():file(file.path):call({}, function(result)
      if result.code == 0 then
        schedule_refresh()
        vim.schedule(callback)
      else
        vim.schedule(function()
          vim.notify("Failed to add file: " .. file.path, vim.log.levels.ERROR)
        end)
      end
    end)
  elseif file.status == "M" then
    -- Modified: add to virtual staging
    staged.stage(file.path)
    -- Trigger re-render to show staged state
    local ok, status = pcall(require, "neosapling.status")
    if ok and status._render then
      status._render()
    end
    callback()
  elseif file.status == "A" then
    -- Already staged (added)
    vim.notify("File already staged", vim.log.levels.INFO)
    callback()
  else
    vim.notify("Cannot stage file with status: " .. (file.status or "unknown"), vim.log.levels.WARN)
    callback()
  end
end

--- Unstage a file based on its current status
---@param file FileStatus The file to unstage
---@param callback? function Called after operation
function M.unstage(file, callback)
  callback = callback or function() end

  if file.status == "A" then
    -- Added: sl forget
    cli.forget():file(file.path):call({}, function(result)
      if result.code == 0 then
        schedule_refresh()
        vim.schedule(callback)
      else
        vim.schedule(function()
          vim.notify("Failed to unstage file: " .. file.path, vim.log.levels.ERROR)
        end)
      end
    end)
  elseif file.status == "M" and staged.is_staged(file.path) then
    -- Modified and virtually staged: remove from virtual staging
    staged.unstage(file.path)
    local ok, status = pcall(require, "neosapling.status")
    if ok and status._render then
      status._render()
    end
    callback()
  else
    vim.notify("File is not staged", vim.log.levels.INFO)
    callback()
  end
end

--- Discard file changes (with confirmation)
---@param file FileStatus The file to discard
---@param callback? function Called after operation
function M.discard(file, callback)
  callback = callback or function() end

  -- Confirmation with default to No (Pitfall #4 from research)
  local choice = vim.fn.confirm(
    "Discard changes to " .. file.path .. "?",
    "&Yes\n&No",
    2  -- Default to No
  )

  if choice ~= 1 then
    callback()
    return
  end

  if file.status == "?" then
    -- Untracked: delete the file
    local ok, err = pcall(vim.fn.delete, file.path)
    if not ok then
      vim.notify("Failed to delete file: " .. (err or "unknown error"), vim.log.levels.ERROR)
    end
    schedule_refresh()
    callback()
  else
    -- Tracked: sl revert --no-backup
    watcher.pause()
    cli.revert():opt("--no-backup"):file(file.path):call({}, function(result)
      if result.code == 0 then
        -- Clear from virtual staging if present
        staged.unstage(file.path)
        watcher.resume()
        schedule_refresh()
        vim.schedule(callback)
      else
        watcher.resume()
        vim.schedule(function()
          vim.notify("Failed to revert file: " .. file.path, vim.log.levels.ERROR)
        end)
      end
    end)
  end
end

return M
