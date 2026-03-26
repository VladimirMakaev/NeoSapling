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

-- Track whether the latest notification includes .sl/ changes
local last_notification_has_sl_changes = false

--- Handle a Watchman notification by debouncing and refreshing.
--- Restarts the debounce timer on each notification so rapid changes
--- (e.g., checkout touching many files) result in a single refresh.
---@param has_sl_changes boolean Whether .sl/ directory changes were detected
local function on_notification(has_sl_changes)
  if paused then
    return
  end

  -- Track if any notification in the debounce window includes .sl/ changes
  if has_sl_changes then
    last_notification_has_sl_changes = true
  end

  -- Create timer if needed
  if not debounce_timer then
    debounce_timer = vim.uv.new_timer()
  end

  -- Stop existing timer if running, then start fresh with 200ms delay
  debounce_timer:stop()
  debounce_timer:start(200, 0, function()
    debounce_timer:stop()
    local full = last_notification_has_sl_changes
    last_notification_has_sl_changes = false

    vim.schedule(function()
      -- Status-only refresh for file changes, full refresh for .sl/ changes
      local ok1, status = pcall(require, "neosapling.status")
      if ok1 and status.refresh then
        status.refresh({ full = full })
      end
      -- Smartlog always gets a full refresh when it refreshes
      if full then
        local ok2, smartlog = pcall(require, "neosapling.smartlog")
        if ok2 and smartlog.refresh then
          smartlog.refresh()
        end
      end
    end)
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
              -- Check if any changed files are in .sl/ directory
              local has_sl = false
              if decoded.files then
                for _, f in ipairs(decoded.files) do
                  if type(f) == "table" and f.name and f.name:match("^%.sl/") then
                    has_sl = true
                    break
                  elseif type(f) == "string" and f:match("^%.sl/") then
                    has_sl = true
                    break
                  end
                end
              end
              on_notification(has_sl)
            elseif ok and decoded and decoded.error then
              vim.schedule(function()
                vim.notify("NeoSapling watcher error: " .. decoded.error, vim.log.levels.WARN)
              end)
            end
          end
        end
      end,
      stderr = function(_, data)
        if data and data ~= "" then
          vim.schedule(function()
            vim.notify("NeoSapling watcher stderr: " .. vim.trim(data), vim.log.levels.DEBUG)
          end)
        end
      end,
    },
    function(obj)
      -- Process exited - clean up state and log exit code
      vim.schedule(function()
        if obj.code ~= 0 then
          vim.notify("NeoSapling watcher exited with code " .. tostring(obj.code), vim.log.levels.DEBUG)
        end
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

--- Check if the watcher is active (subscription running).
---@return boolean
function M.is_active()
  return subscription_name ~= nil and watch_process ~= nil
end

--- Get watcher status info for diagnostics.
---@return table {available: boolean, active: boolean, paused: boolean, views: table}
function M.get_status()
  return {
    available = M.is_available(),
    active = M.is_active(),
    paused = paused,
    subscription = subscription_name,
    views = vim.deepcopy(open_buffers),
  }
end

--- Setup the :NeoSaplingWatcher user command for diagnostics.
function M.setup_command()
  vim.api.nvim_create_user_command("NeoSaplingWatcher", function()
    local status = M.get_status()
    local lines = {
      "NeoSapling Watcher Status:",
      "  Watchman available: " .. tostring(status.available),
      "  Subscription active: " .. tostring(status.active),
      "  Paused: " .. tostring(status.paused),
      "  Subscription name: " .. (status.subscription or "none"),
      "  Open views: status=" .. tostring(status.views.status) .. ", smartlog=" .. tostring(status.views.smartlog),
    }
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, { desc = "Show NeoSapling watcher status" })
end

return M
