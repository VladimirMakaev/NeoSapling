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

--- Handle a Watchman notification by debouncing and refreshing.
---@param has_vcs_changes boolean Whether VCS directory changes were detected
local function on_notification(has_vcs_changes)
  if paused then
    return
  end

  if not debounce_timer then
    debounce_timer = vim.uv.new_timer()
  end

  debounce_timer:stop()
  debounce_timer:start(200, 0, function()
    debounce_timer:stop()

    vim.schedule(function()
      local ok1, status = pcall(require, "neosapling.status")
      if ok1 and status.refresh then
        status.refresh({ full = has_vcs_changes })
      end
      if has_vcs_changes then
        local ok2, smartlog = pcall(require, "neosapling.smartlog")
        if ok2 and smartlog.refresh then
          smartlog.refresh()
        end
      end
    end)
  end)
end

--- Start a Watchman subscription on the repository root.
--- Uses a 3-step CLI protocol: watch-project → clock → subscribe.
local function start_subscription()
  if not M.is_available() then
    return
  end

  if subscription_name then
    return
  end

  local util = require("neosapling.lib.util")
  local root = util.find_root()
  if not root then
    return
  end

  subscription_name = "neosapling-" .. vim.fn.getpid()

  -- State machine for the 3-step handshake
  -- watchman -j -p: JSON protocol mode with persistent connection
  local state = 0  -- 0=init, 1=watch-project sent, 2=clock sent, 3=subscribe sent, 4=active
  local watch_root = root
  local read_buffer = ""
  local has_pending_vcs = false

  local function handle_response(decoded)
    if state == 1 then
      -- watch-project response
      watch_root = decoded.watch or root
      state = 2
      -- Send clock command
      local clock_cmd = vim.json.encode({ "clock", watch_root }) .. "\n"
      watch_process:write(clock_cmd)
    elseif state == 2 then
      -- clock response
      state = 3
      local subscribe_cmd = vim.json.encode({
        "subscribe", watch_root, subscription_name,
        {
          fields = { "name" },
          since = decoded.clock,
          defer = { "sl.update" },
        },
      }) .. "\n"
      watch_process:write(subscribe_cmd)
    elseif state == 3 then
      -- subscribe response
      if decoded.subscribe then
        state = 4
      end
    elseif state == 4 then
      -- File change notification
      if decoded.subscription then
        local files = decoded.files
        if not files or #files == 0 then return end

        local has_vcs = false
        for _, f in ipairs(files) do
          local name = type(f) == "table" and f.name or (type(f) == "string" and f or nil)
          if name and (name:match("^%.sl/") or name:match("^%.hg/") or name:match("^%.edenfs")) then
            has_vcs = true
            break
          end
        end
        on_notification(has_vcs)
      end
    end
  end

  watch_process = vim.system(
    { "watchman", "-j", "--no-pretty", "-p" },
    {
      stdin = true,
      cwd = root,
      text = true,
      stdout = function(_, data)
        if not data then return end
        read_buffer = read_buffer .. data
        while true do
          local newline = read_buffer:find("\n")
          if not newline then break end
          local line = read_buffer:sub(1, newline - 1)
          read_buffer = read_buffer:sub(newline + 1)
          if line ~= "" then
            local ok, decoded = pcall(vim.json.decode, line)
            if ok and decoded then
              handle_response(decoded)
            end
          end
        end
      end,
    },
    function(obj)
      -- Process exited
      vim.schedule(function()
        subscription_name = nil
        watch_process = nil
      end)
    end
  )

  -- Kick off handshake: send watch-project
  state = 1
  local watch_cmd = vim.json.encode({ "watch-project", root }) .. "\n"
  watch_process:write(watch_cmd)
end

--- Stop the Watchman subscription and clean up all state.
local function stop_subscription()
  if watch_process then
    pcall(function()
      watch_process:kill("SIGTERM")
    end)
    watch_process = nil
  end

  subscription_name = nil

  if debounce_timer then
    debounce_timer:stop()
    debounce_timer:close()
    debounce_timer = nil
  end

  if pause_timer then
    pause_timer:stop()
    pause_timer:close()
    pause_timer = nil
  end

  paused = false
end

--- Notify that a view has been opened.
---@param view_name string Either "status" or "smartlog"
function M.notify_open(view_name)
  open_buffers[view_name] = true

  if not subscription_name then
    start_subscription()
  end
end

--- Notify that a view has been closed.
---@param view_name string Either "status" or "smartlog"
function M.notify_close(view_name)
  open_buffers[view_name] = false

  if not open_buffers.status and not open_buffers.smartlog then
    stop_subscription()
  end
end

--- Pause refresh notifications temporarily.
function M.pause()
  paused = true

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
---@return table
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
    local s = M.get_status()
    local lines = {
      "NeoSapling Watcher Status:",
      "  Watchman available: " .. tostring(s.available),
      "  Subscription active: " .. tostring(s.active),
      "  Subscription name: " .. (s.subscription or "none"),
      "  Paused: " .. tostring(s.paused),
      "  Open views: status=" .. tostring(s.views.status) .. ", smartlog=" .. tostring(s.views.smartlog),
    }
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, { desc = "Show NeoSapling watcher status" })
end

return M
