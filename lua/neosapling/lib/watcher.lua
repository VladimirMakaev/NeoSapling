--- Watchman-based file watcher for NeoSapling.
--- Monitors file changes via Watchman subscriptions and triggers
--- debounced refreshes of status and smartlog views.
--- Connects directly to the Watchman Unix socket (bypasses CLI fchmod issues).
--- Gracefully degrades to no-ops when Watchman is not available.
--- @module neosapling.lib.watcher

local M = {}

-- Module state
local available = nil -- Cached availability result (nil = not checked)
local sock_path = nil -- Cached socket path
local subscription_name = nil -- Active subscription name
local sock_handle = nil -- uv_pipe_t for the Watchman socket connection
local debounce_timer = nil -- uv_timer_t for debouncing notifications
local paused = false -- Whether refresh is suppressed (during own operations)
local pause_timer = nil -- Safety-net timer for auto-resume
local read_buffer = "" -- Accumulated data from socket reads

-- Track which views are currently open
local open_buffers = {
  status = false,
  smartlog = false,
}

--- Find the Watchman socket path.
--- Tries standard locations for the current user.
---@return string|nil
local function find_sock_path()
  if sock_path then return sock_path end

  -- Try common locations
  local user = vim.env.USER or vim.fn.expand("$USER")
  local candidates = {
    "/opt/facebook/watchman/var/run/watchman/" .. user .. "-state/sock",
    "/tmp/watchman-" .. user .. "/sock",
    vim.env.HOME and (vim.env.HOME .. "/.watchman/sock") or nil,
  }

  for _, path in ipairs(candidates) do
    if path and vim.uv.fs_stat(path) then
      sock_path = path
      return sock_path
    end
  end

  -- Try watchman get-sockname as last resort (may fail with fchmod)
  local result = vim.system({ "watchman", "get-sockname" }, { text = true }):wait()
  if result.code == 0 and result.stdout then
    local ok, decoded = pcall(vim.json.decode, table.concat(type(result.stdout) == "table" and result.stdout or { result.stdout }, ""))
    if ok and decoded and decoded.sockname then
      sock_path = decoded.sockname
      return sock_path
    end
  end

  return nil
end

--- Check if Watchman is available by testing the socket.
--- Caches the result after first check.
---@return boolean
function M.is_available()
  if available == nil then
    available = find_sock_path() ~= nil
  end
  return available
end

-- Track whether the latest notification includes .sl/ changes
local last_notification_has_sl_changes = false

--- Handle a Watchman notification by debouncing and refreshing.
---@param has_sl_changes boolean Whether .sl/ directory changes were detected
local function on_notification(has_sl_changes)
  if paused then
    return
  end

  if has_sl_changes then
    last_notification_has_sl_changes = true
  end

  if not debounce_timer then
    debounce_timer = vim.uv.new_timer()
  end

  debounce_timer:stop()
  debounce_timer:start(200, 0, function()
    debounce_timer:stop()
    local full = last_notification_has_sl_changes
    last_notification_has_sl_changes = false

    vim.schedule(function()
      local ok1, status = pcall(require, "neosapling.status")
      if ok1 and status.refresh then
        status.refresh({ full = full })
      end
      if full then
        local ok2, smartlog = pcall(require, "neosapling.smartlog")
        if ok2 and smartlog.refresh then
          smartlog.refresh()
        end
      end
    end)
  end)
end

--- Start a Watchman subscription via Unix socket.
--- Uses a 3-step handshake: watch-project → clock → subscribe.
local function start_subscription()
  if not M.is_available() then
    return
  end

  if subscription_name then
    return
  end

  local path = find_sock_path()
  if not path then return end

  local util = require("neosapling.lib.util")
  local root = util.find_root()
  if not root then return end

  local sub_name = "neosapling-" .. vim.fn.getpid()
  subscription_name = sub_name
  read_buffer = ""

  local pipe = vim.uv.new_pipe(false)
  if not pipe then
    subscription_name = nil
    return
  end

  -- State machine: tracks which step we're on
  -- 1 = waiting for watch-project response
  -- 2 = waiting for clock response
  -- 3 = waiting for subscribe response
  -- 4 = subscribed, processing notifications
  local state = 0
  local watch_root = root

  local function send(cmd)
    pipe:write(vim.json.encode(cmd) .. "\n")
  end

  local function handle_response(decoded)
    if state == 1 then
      -- watch-project response
      watch_root = decoded.watch or root
      state = 2
      send({ "clock", watch_root })
    elseif state == 2 then
      -- clock response
      local clock = decoded.clock
      state = 3
      send({
        "subscribe", watch_root, sub_name,
        {
          fields = { "name" },
          since = clock,
          defer = { "sl.update" },
        },
      })
    elseif state == 3 then
      -- subscribe response
      if decoded.subscribe then
        state = 4
        sock_handle = pipe
      else
        vim.schedule(function()
          vim.notify("NeoSapling: Watchman subscribe failed: " .. vim.json.encode(decoded), vim.log.levels.WARN)
        end)
      end
    elseif state == 4 then
      -- File change notification
      if decoded.subscription then
        local has_sl = false
        if decoded.files then
          for _, f in ipairs(decoded.files) do
            local name = type(f) == "table" and f.name or (type(f) == "string" and f or nil)
            if name and (name:match("^%.sl/") or name:match("^%.hg/")) then
              has_sl = true
              break
            end
          end
        end
        on_notification(has_sl)
      elseif decoded.error then
        vim.schedule(function()
          vim.notify("NeoSapling watcher error: " .. decoded.error, vim.log.levels.WARN)
        end)
      end
    end
  end

  pipe:connect(path, function(err)
    if err then
      vim.schedule(function()
        vim.notify("NeoSapling: Failed to connect to Watchman socket: " .. tostring(err), vim.log.levels.DEBUG)
      end)
      pipe:close()
      subscription_name = nil
      return
    end

    -- Start reading responses
    pipe:read_start(function(read_err, data)
      if read_err then
        vim.schedule(function()
          vim.notify("NeoSapling watcher read error: " .. tostring(read_err), vim.log.levels.DEBUG)
        end)
        return
      end
      if not data then
        -- EOF
        vim.schedule(function()
          subscription_name = nil
          sock_handle = nil
        end)
        return
      end

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
    end)

    -- Kick off the handshake
    state = 1
    send({ "watch-project", root })
  end)
end

--- Stop the Watchman subscription and clean up all state.
local function stop_subscription()
  if sock_handle then
    -- Send unsubscribe before closing
    if subscription_name then
      local util = require("neosapling.lib.util")
      local root = util.find_root()
      if root then
        local unsub = vim.json.encode({ "unsubscribe", root, subscription_name }) .. "\n"
        pcall(function() sock_handle:write(unsub) end)
      end
    end
    pcall(function()
      sock_handle:read_stop()
      sock_handle:close()
    end)
    sock_handle = nil
  end

  subscription_name = nil
  read_buffer = ""

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
  return subscription_name ~= nil and sock_handle ~= nil
end

--- Get watcher status info for diagnostics.
---@return table
function M.get_status()
  return {
    available = M.is_available(),
    active = M.is_active(),
    paused = paused,
    subscription = subscription_name,
    socket_path = sock_path,
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
      "  Socket path: " .. (s.socket_path or "not found"),
      "  Subscription active: " .. tostring(s.active),
      "  Subscription name: " .. (s.subscription or "none"),
      "  Paused: " .. tostring(s.paused),
      "  Open views: status=" .. tostring(s.views.status) .. ", smartlog=" .. tostring(s.views.smartlog),
    }
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, { desc = "Show NeoSapling watcher status" })
end

return M
