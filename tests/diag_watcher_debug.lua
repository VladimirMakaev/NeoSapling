-- Direct watcher debug — logs every step to /tmp/neosapling_wdebug.log
-- Run: :luafile /Users/vmakaev/NonWork/NeoSapling/tests/diag_watcher_debug.lua

local LOG = "/tmp/neosapling_wdebug.log"
local L = {}
local function log(msg) table.insert(L, os.date("%H:%M:%S") .. " " .. msg) end
local function flush() pcall(vim.fn.writefile, L, LOG) end

local sock_path = "/opt/facebook/watchman/var/run/watchman/vmakaev-state/sock"

-- Find repo root
local root_result = vim.system({"hg", "root"}, {text = true, cwd = vim.fn.getcwd()}):wait()
local root = root_result.code == 0 and vim.trim(root_result.stdout or "") or nil
log("root: " .. tostring(root))
log("sock: " .. sock_path)

if not root then log("NO ROOT"); flush(); return end

local pipe = vim.uv.new_pipe(false)
log("pipe: " .. tostring(pipe ~= nil))

local state = 0
local buf = ""

pipe:connect(sock_path, function(err)
  if err then
    log("CONNECT ERR: " .. tostring(err))
    vim.schedule(flush)
    return
  end
  log("CONNECTED")

  pipe:read_start(function(rerr, data)
    if rerr then log("READ ERR: " .. tostring(rerr)); vim.schedule(flush); return end
    if not data then log("EOF"); vim.schedule(flush); return end

    buf = buf .. data
    while true do
      local nl = buf:find("\n")
      if not nl then break end
      local line = buf:sub(1, nl - 1)
      buf = buf:sub(nl + 1)
      if line == "" then goto continue end

      local ok, d = pcall(vim.json.decode, line)
      if not ok then log("JSON ERR: " .. line:sub(1,100)); goto continue end

      if state == 1 then
        log("watch-project resp: watch=" .. tostring(d.watch))
        state = 2
        pipe:write(vim.json.encode({"clock", d.watch or root}) .. "\n")
        log("sent clock")
      elseif state == 2 then
        log("clock resp: " .. tostring(d.clock))
        state = 3
        local sub = vim.json.encode({"subscribe", root, "dbg-sub", {fields={"name"}, since=d.clock}}) .. "\n"
        pipe:write(sub)
        log("sent subscribe")
      elseif state == 3 then
        log("subscribe resp: " .. line:sub(1, 200))
        state = 4
        log("SUBSCRIBED! Waiting for notifications...")
      elseif state == 4 then
        local nfiles = d.files and #d.files or 0
        log("NOTIFICATION: " .. nfiles .. " files changed")
        if d.files then
          for i, f in ipairs(d.files) do
            if i <= 5 then
              local name = type(f) == "table" and f.name or tostring(f)
              log("  " .. name)
            end
          end
          if nfiles > 5 then log("  ... and " .. (nfiles-5) .. " more") end
        end
      end

      ::continue::
    end
    vim.schedule(flush)
  end)

  state = 1
  pipe:write(vim.json.encode({"watch-project", root}) .. "\n")
  log("sent watch-project")
  vim.schedule(flush)
end)

-- Wait and flush periodically
for _ = 1, 60 do
  vim.wait(1000, function() return false end, 100)
  flush()
  if state == 4 then break end
end

log("final state: " .. state)
flush()
print("Log at " .. LOG)
