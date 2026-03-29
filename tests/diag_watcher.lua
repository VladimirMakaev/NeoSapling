-- Watchman socket connection test
-- Run: :luafile tests/diag_watcher.lua
-- Read: /tmp/neosapling_watcher.log

local lines = {}
local function log(msg) table.insert(lines, msg) end
local function flush() vim.fn.writefile(lines, "/tmp/neosapling_watcher.log") end

vim.opt.runtimepath:prepend(vim.fn.getcwd())
for mod_name, _ in pairs(package.loaded) do
  if mod_name:match("^neosapling") then package.loaded[mod_name] = nil end
end

require("neosapling").setup()

local watcher = require("neosapling.lib.watcher")

log("=== Watchman Watcher Test ===")
log("")

-- Test 1: is_available
local avail = watcher.is_available()
log("is_available: " .. tostring(avail))

-- Test 2: get_status before open
local s1 = watcher.get_status()
log("socket_path: " .. (s1.socket_path or "NOT FOUND"))
log("active before open: " .. tostring(s1.active))

-- Test 3: Try connecting
log("")
log("Opening status view to trigger subscription...")
local status = require("neosapling.status")
status.open()

-- Wait for async subscription to establish
vim.wait(3000, function()
  return watcher.is_active()
end, 100)

local s2 = watcher.get_status()
log("active after open: " .. tostring(s2.active))
log("subscription: " .. (s2.subscription or "none"))

if s2.active then
  log("")
  log("SUCCESS: Watchman subscription is active!")
  log("The watcher will auto-refresh when files change.")
  log("")
  log("To test: modify a file in another terminal and watch the status view update.")
else
  log("")
  log("FAILED: Subscription not active.")
  log("Check socket path exists: " .. (s2.socket_path or "nil"))
  if s2.socket_path then
    local stat = vim.uv.fs_stat(s2.socket_path)
    log("Socket file exists: " .. tostring(stat ~= nil))
    if stat then log("Socket type: " .. stat.type) end
  end

  -- Try raw socket connection for diagnostics
  log("")
  log("Attempting raw socket connection...")
  local pipe = vim.uv.new_pipe(false)
  if pipe and s2.socket_path then
    local connected = false
    local connect_err = nil
    pipe:connect(s2.socket_path, function(err)
      if err then
        connect_err = err
      else
        connected = true
        pipe:write('["version"]\n')
        pipe:read_start(function(_, data)
          if data then
            vim.schedule(function()
              log("Socket response: " .. vim.trim(data))
              flush()
            end)
          end
        end)
      end
    end)
    vim.wait(2000, function() return connected or connect_err ~= nil end, 100)
    log("Raw connect result: connected=" .. tostring(connected) .. " err=" .. tostring(connect_err))
    vim.wait(1000)
    pcall(function() pipe:close() end)
  end
end

status.close()
flush()
print("Written to /tmp/neosapling_watcher.log")
