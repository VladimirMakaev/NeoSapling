--- Watchman-based file watcher for NeoSapling.
--- Monitors file changes via Watchman subscriptions and triggers
--- debounced refreshes of status and smartlog views.
--- Gracefully degrades to no-ops when Watchman is not available.
--- @module neosapling.lib.watcher

local M = {}

-- Module state
local available = nil -- Cached availability result (nil = not checked)
local subscription_name = nil -- Active subscription name
local watch_process = nil -- vim.SystemObj for the Watchman subscribe process
local debounce_timer = nil -- uv_timer_t for debouncing notifications
local paused = false -- Whether refresh is suppressed (during own operations)
local pause_timer = nil -- Safety-net timer for auto-resume

-- Track which views are currently open
local open_buffers = {
  status = false,
  smartlog = false,
}

--- Check if Watchman is available on the system.
--- Caches the result after first check.
---@return boolean
function M.is_available()
  if available == nil then
    available = vim.fn.executable("watchman") == 1
  end
  return available
end

--- Schedule a dual-view refresh of both status and smartlog.
--- Same pattern as actions/stack.lua schedule_refresh.
local function schedule_refresh()
  vim.schedule(function()
    local ok1, status = pcall(require, "neosapling.status")
    if ok1 and status.refresh then
      status.refresh()
    end
    local ok2, smartlog = pcall(require, "neosapling.smartlog")
    if ok2 and smartlog.refresh then
      smartlog.refresh()
    end
  end)
end

--- Handle a Watchman notification by debouncing and refreshing.
--- Restarts the debounce timer on each notification so rapid changes
--- (e.g., checkout touching many files) result in a single refresh.
local function on_notification()
  if paused then
    return
  end

  -- Create timer if needed
  if not debounce_timer then
    debounce_timer = vim.uv.new_timer()
  end

  -- Stop existing timer if running, then start fresh with 200ms delay
  debounce_timer:stop()
  debounce_timer:start(200, 0, function()
    debounce_timer:stop()
    schedule_refresh()
  end)
end

--- Start a Watchman subscription on the repository root.
--- Subscribes to file change notifications and routes them through
--- the debounced refresh handler.
local function start_subscription()
  if not M.is_available() then
    return
  end

  -- Already subscribed
  if subscription_name then
    return
  end

  local util = require("neosapling.lib.util")
  local root = util.find_root()
  if not root then
    return
  end

  -- Generate unique subscription name using PID
  subscription_name = "neosapling-" .. vim.fn.getpid()

  -- Build the subscribe JSON command
  -- Uses defer to pause during Sapling's own operations (sl.update)
  local subscribe_cmd = vim.json.encode({
    "subscribe",
    root,
    subscription_name,
    {
      fields = { "name" },
      since = "c:0:0",
      defer = { "sl.update" },
      expression = { "anyof", { "dirname", ".sl" }, { "match", "**" } },
    },
  })

  -- Run watchman with JSON protocol via stdin
  watch_process = vim.system(
    { "watchman", "-j", "--no-pretty", "-p" },
    {
      stdin = subscribe_cmd .. "\n",
      cwd = root,
      text = true,
      stdout = function(_, data)
        if not data then
          return
        end
        -- Each line from Watchman is a JSON message
        local lines = vim.split(data, "\n", { plain = true })
        for _, line in ipairs(lines) do
          if line ~= "" then
            local ok, decoded = pcall(vim.json.decode, line)
            if ok and decoded and decoded.subscription then
              -- This is a file change notification
              on_notification()
            end
          end
        end
      end,
    },
    function(_)
      -- Process exited - clean up state
      vim.schedule(function()
        subscription_name = nil
        watch_process = nil
      end)
    end
  )
end

--- Stop the Watchman subscription and clean up all state.
local function stop_subscription()
  -- Kill the Watchman process
  if watch_process then
    pcall(function()
      watch_process:kill("SIGTERM")
    end)
    watch_process = nil
  end

  subscription_name = nil

  -- Stop and close debounce timer
  if debounce_timer then
    debounce_timer:stop()
    debounce_timer:close()
    debounce_timer = nil
  end

  -- Stop pause timer if active
  if pause_timer then
    pause_timer:stop()
    pause_timer:close()
    pause_timer = nil
  end

  paused = false
end

--- Notify that a view has been opened.
--- Starts the Watchman subscription if this is the first view to open.
---@param view_name string Either "status" or "smartlog"
function M.notify_open(view_name)
  open_buffers[view_name] = true

  -- Start subscription if not already active
  if not subscription_name then
    start_subscription()
  end
end

--- Notify that a view has been closed.
--- Stops the Watchman subscription if no views remain open.
---@param view_name string Either "status" or "smartlog"
function M.notify_close(view_name)
  open_buffers[view_name] = false

  -- If no views remain open, stop subscription
  if not open_buffers.status and not open_buffers.smartlog then
    stop_subscription()
  end
end

--- Pause refresh notifications temporarily.
--- Used during NeoSapling's own operations (stage, commit, etc.)
--- to avoid double-refreshing since those operations already call
--- schedule_refresh() themselves.
--- Auto-resumes after 2 seconds as a safety net.
function M.pause()
  paused = true

  -- Safety-net: auto-resume after 2 seconds
  if pause_timer then
    pause_timer:stop()
    pause_timer:close()
  end
  pause_timer = vim.uv.new_timer()
  pause_timer:start(2000, 0, function()
    paused = false
    if pause_timer then
      pause_timer:stop()
      pause_timer:close()
      pause_timer = nil
    end
  end)
end

--- Resume refresh notifications after a pause.
function M.resume()
  paused = false
  if pause_timer then
    pause_timer:stop()
    pause_timer:close()
    pause_timer = nil
  end
end

return M
