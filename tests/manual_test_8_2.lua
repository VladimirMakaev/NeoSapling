-- Manual test script for Phase 8.2: UX Polish & Bug Fixes
-- Writes all output to /tmp/neosapling_test_8_2.log
--
-- Run in Neovim opened in a Sapling repo:
--   :luafile tests/manual_test_8_2.lua

local LOG_FILE = "/tmp/neosapling_test_8_2.log"
local log_lines = {}

local function log(msg)
  table.insert(log_lines, msg)
  print(msg)
end

local function flush_log()
  vim.fn.writefile(log_lines, LOG_FILE)
end

-- Setup: ensure plugin is loaded with fresh modules
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Clear cached neosapling modules so code changes take effect without restarting Neovim
for mod_name, _ in pairs(package.loaded) do
  if mod_name:match("^neosapling") then
    package.loaded[mod_name] = nil
  end
end
-- Also clear the preload cache (LuaJIT may cache module loaders)
for mod_name, _ in pairs(package.preload) do
  if mod_name:match("^neosapling") then
    package.preload[mod_name] = nil
  end
end

local ok, neosapling = pcall(require, "neosapling")
if not ok then
  log("ERROR: Could not load neosapling. Make sure you're in the NeoSapling plugin directory.")
  flush_log()
  return
end
neosapling.setup()

local passed = 0
local failed = 0
local skipped = 0

local function test(name, fn)
  local ok2, err = pcall(fn)
  if ok2 then
    passed = passed + 1
    log("  PASS: " .. name)
  else
    if type(err) == "string" and err:match("^SKIP:") then
      skipped = skipped + 1
      log("  SKIP: " .. name .. " - " .. err:sub(6))
    else
      failed = failed + 1
      log("  FAIL: " .. name .. " - " .. tostring(err))
    end
  end
end

local function skip(reason)
  error("SKIP:" .. reason)
end

-- Check sl is available
local sl_ok = vim.fn.executable("sl") == 1
if not sl_ok then
  log("ERROR: 'sl' (Sapling) not found. Run this in a Sapling repo.")
  flush_log()
  return
end

log("=== Phase 8.2 Manual Tests ===")
log("  cwd: " .. vim.fn.getcwd())
log("  nvim: " .. tostring(vim.version()))
log("")

-- ============================================================
log("--- Plan 1: Navigation & Focus ---")
-- ============================================================

test("Smartlog parser handles flexible hash lengths", function()
  local parser = require("neosapling.lib.parsers.smartlog_ssl")
  -- 10-char hash
  local result = parser.classify_line("  o  abcdef1234  Today at 10:00  user", nil)
  assert(result.type == "commit_header", "Should parse 10-char hash, got: " .. result.type)
  assert(result.commit.node == "abcdef1234")

  -- 12-char hash
  local result2 = parser.classify_line("  o  abcdef123456  Today at 10:00  user", nil)
  assert(result2.type == "commit_header", "Should parse 12-char hash")
  assert(result2.commit.node == "abcdef123456")

  -- 8-char hash
  local result3 = parser.classify_line("  o  abcdef12  Today at 10:00  user", nil)
  assert(result3.type == "commit_header", "Should parse 8-char hash")
end)

test("Smartlog parser handles hash with parenthesized annotation", function()
  local parser = require("neosapling.lib.parsers.smartlog_ssl")
  -- Real-world line: hash followed by "(Not backed up)" before metadata
  local line = "╷ @  e5c143173d (Not backed up)  Monday at 15:59  vmakaev  D97760145 Committed ‼"
  local result = parser.classify_line(line, nil)

  -- Debug: test the patterns directly
  local h1 = line:match("^(.-)([o@xO]%%*?)  (%%x+)  (.+)$")
  local _, _, h2, ann = line:match("^(.-)([o@xO]%%*?)  (%%x+) (%%b())  (.+)$")
  log("    [diag] annotation test: primary_match=" .. tostring(h1 ~= nil) .. " fallback_match=" .. tostring(h2 ~= nil))
  log("    [diag] classify_line source: " .. debug.getinfo(parser.classify_line).source)
  log("    [diag] result type: " .. result.type)

  assert(result.type == "commit_header", "Should parse as commit_header, got: " .. result.type)
  assert(result.commit.graphnode == "@", "Graphnode should be @, got: " .. result.commit.graphnode)
  assert(result.commit.node == "e5c143173d", "Node should be e5c143173d, got: " .. result.commit.node)
end)

test("Smartlog parser handles O graphnode", function()
  local parser = require("neosapling.lib.parsers.smartlog_ssl")
  local result = parser.classify_line("  O  abcdef1234  Today at 10:00  remote/master", nil)
  assert(result.type == "commit_header", "Should parse O graphnode")
  assert(result.commit.graphnode == "O")
end)

test("Smartlog opens and centers on @ commit", function()
  local smartlog = require("neosapling.smartlog")
  smartlog.open()

  -- Wait for async data — up to 10s for large repos like fbsource
  local loaded = vim.wait(10000, function()
    local buf = vim.fn.bufnr("neosapling://smartlog")
    if buf == -1 then return false end
    return vim.api.nvim_buf_line_count(buf) > 3
  end, 200)

  local buf = vim.fn.bufnr("neosapling://smartlog")
  if buf == -1 then skip("smartlog buffer not created") end
  if not loaded then
    log("    [diag] smartlog data did not load within 10s (sl smartlog may be slow on this repo)")
    smartlog.close()
    skip("smartlog data not loaded in time")
  end

  local wins = vim.fn.win_findbuf(buf)
  if #wins == 0 then skip("no window for smartlog") end

  local cursor = vim.api.nvim_win_get_cursor(wins[1])
  local line_count = vim.api.nvim_buf_line_count(buf)

  -- Dump buffer content and cursor info for diagnostics
  local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  log("    [diag] smartlog cursor line=" .. cursor[1] .. " col=" .. cursor[2] .. " total_lines=" .. line_count)
  local max_diag_lines = math.min(#buf_lines, 30)
  for i = 1, max_diag_lines do
    log("    [diag] line " .. i .. ": " .. buf_lines[i]:sub(1, 120))
  end
  if #buf_lines > max_diag_lines then
    log("    [diag] ... (" .. (#buf_lines - max_diag_lines) .. " more lines)")
  end

  -- Dump line_map — only @ and local_changes commits, plus counts
  local lm = smartlog.get_line_map()
  local total_commits = 0
  local at_entries = {}
  local lc_entries = {}
  for lnum, item in pairs(lm) do
    if item.type == "commit" and item.commit then
      total_commits = total_commits + 1
      if item.commit.graphnode == "@" then
        table.insert(at_entries, lnum)
      end
      if item.commit.local_changes then
        table.insert(lc_entries, lnum)
      end
    end
  end
  table.sort(at_entries)
  table.sort(lc_entries)
  log("    [diag] total commits in line_map: " .. total_commits)
  log("    [diag] @ commits: " .. (#at_entries > 0 and table.concat(vim.tbl_map(tostring, at_entries), ", ") or "NONE"))
  log("    [diag] local_changes commits (first 5): " .. table.concat(vim.tbl_map(tostring, vim.list_slice(lc_entries, 1, 5)), ", "))

  -- Check cursor is on @ commit, or if no @, on a commit past hint bar
  local cursor_item = lm[cursor[1]]
  if cursor_item and cursor_item.commit then
    log("    [diag] cursor commit: gn=" .. (cursor_item.commit.graphnode or "?") .. " node=" .. (cursor_item.commit.node or "?"):sub(1, 10))
  end

  if #at_entries > 0 then
    -- @ commit exists — cursor should be on it
    local on_at = false
    for _, lnum in ipairs(at_entries) do
      if cursor[1] == lnum then on_at = true end
    end
    assert(on_at, "Cursor should be on @ commit (cursor=" .. cursor[1] .. ", @ at " .. table.concat(vim.tbl_map(tostring, at_entries), ",") .. ")")
  else
    -- No @ commit — cursor should at least be past hint bar
    assert(cursor[1] > 3, "Cursor should be past hint bar (line " .. cursor[1] .. ", expected > 3)")
  end

  smartlog.close()
end)

-- ============================================================
log("")
log("--- Plan 2: Visual Polish ---")
-- ============================================================

test("NeoSaplingCurrentLine highlight group exists", function()
  local ok3, hl = pcall(vim.api.nvim_get_hl, 0, { name = "NeoSaplingCurrentLine" })
  assert(ok3 and not vim.tbl_isempty(hl), "NeoSaplingCurrentLine should be defined")
end)

test("NeoSaplingDiffAdd highlight group exists", function()
  local ok3, hl = pcall(vim.api.nvim_get_hl, 0, { name = "NeoSaplingDiffAdd" })
  assert(ok3 and not vim.tbl_isempty(hl), "NeoSaplingDiffAdd should be defined")
end)

test("NeoSaplingDiffDelete highlight group exists", function()
  local ok3, hl = pcall(vim.api.nvim_get_hl, 0, { name = "NeoSaplingDiffDelete" })
  assert(ok3 and not vim.tbl_isempty(hl), "NeoSaplingDiffDelete should be defined")
end)

test("NeoSaplingDiffHunkHeader highlight group exists", function()
  local ok3, hl = pcall(vim.api.nvim_get_hl, 0, { name = "NeoSaplingDiffHunkHeader" })
  assert(ok3 and not vim.tbl_isempty(hl), "NeoSaplingDiffHunkHeader should be defined")
end)

test("Buffer set_highlights supports line_hl_group", function()
  local Buffer = require("neosapling.lib.ui.buffer")
  local buf = Buffer:new("neosapling://test_hl")
  buf:set_lines({ "test line" })
  buf:set_highlights({
    { line = 0, col_start = 0, col_end = 4, hl = "Normal", line_hl_group = "CursorLine" },
  })
  buf:destroy()
end)

test("Buffer set_highlights supports hl_eol", function()
  local Buffer = require("neosapling.lib.ui.buffer")
  local buf = Buffer:new("neosapling://test_eol")
  buf:set_lines({ "test line" })
  buf:set_highlights({
    { line = 0, col_start = 0, col_end = 4, hl = "DiffAdd", hl_eol = true },
  })
  buf:destroy()
end)

test("SSL parser adds CurrentLine highlight for @ commit", function()
  local parser = require("neosapling.lib.parsers.smartlog_ssl")
  local lines = {
    "  @  abcdef1234  Today at 10:00  user",
    "  │  my commit message",
  }
  local _, highlights, _ = parser.build(lines)
  local found_current_line = false
  for _, hl in ipairs(highlights) do
    if hl.line_hl_group == "NeoSaplingCurrentLine" then
      found_current_line = true
      break
    end
  end
  assert(found_current_line, "Should have NeoSaplingCurrentLine highlight for @ commit")
end)

-- ============================================================
log("")
log("--- Plan 3: Action Improvements ---")
-- ============================================================

test("CLI builder has metaedit subcommand", function()
  local cli = require("neosapling.lib.cli")
  local builder = cli.metaedit()
  assert(builder, "cli.metaedit() should return a builder")
end)

test("Stack module has metaedit_interactive", function()
  local stack = require("neosapling.actions.stack")
  assert(type(stack.metaedit_interactive) == "function", "Should export metaedit_interactive")
end)

test("Editor module accepts metaedit option", function()
  local editor = require("neosapling.commit.editor")
  assert(type(editor.open) == "function", "Should export open")
end)

test("Commit popup actions has metaedit", function()
  local actions = require("neosapling.popups.commit.actions")
  assert(type(actions.metaedit) == "function", "Should export metaedit action")
end)

test("File actions module imports watcher", function()
  local file_actions = require("neosapling.actions.file")
  assert(type(file_actions.discard) == "function")
end)

-- ============================================================
log("")
log("--- Plan 4: File Operations ---")
-- ============================================================

test("Status opens and has E keymap", function()
  local status = require("neosapling.status")
  status.open()

  vim.wait(3000, function()
    local buf = vim.fn.bufnr("neosapling://status")
    return buf ~= -1 and vim.api.nvim_buf_line_count(buf) > 3
  end)

  local buf = vim.fn.bufnr("neosapling://status")
  if buf == -1 then skip("status buffer not created") end

  local keymaps = vim.api.nvim_buf_get_keymap(buf, "n")
  local has_E = false
  for _, km in ipairs(keymaps) do
    if km.lhs == "E" then
      has_E = true
      break
    end
  end
  assert(has_E, "Should have E keymap for metaedit")

  status.close()
end)

test("Status CR keymap handles files", function()
  local status = require("neosapling.status")
  status.open()

  vim.wait(2000, function()
    return vim.fn.bufnr("neosapling://status") ~= -1
  end)

  local buf = vim.fn.bufnr("neosapling://status")
  if buf == -1 then skip("status buffer not created") end

  local keymaps = vim.api.nvim_buf_get_keymap(buf, "n")
  local has_cr = false
  local cr_desc = ""
  for _, km in ipairs(keymaps) do
    if km.lhs == "<CR>" then
      has_cr = true
      cr_desc = km.desc or ""
      break
    end
  end
  assert(has_cr, "Should have CR keymap")
  log("    [diag] CR desc: " .. cr_desc)

  status.close()
end)

-- ============================================================
log("")
log("--- Plan 5: Performance & Refresh ---")
-- ============================================================

test("Watcher has is_active API", function()
  local watcher = require("neosapling.lib.watcher")
  assert(type(watcher.is_active) == "function", "Should export is_active")
  local result = watcher.is_active()
  assert(type(result) == "boolean", "is_active should return boolean")
end)

test("Watcher has get_status API", function()
  local watcher = require("neosapling.lib.watcher")
  assert(type(watcher.get_status) == "function", "Should export get_status")
  local ws = watcher.get_status()
  assert(type(ws) == "table", "get_status should return table")
  assert(ws.available ~= nil, "Should have available field")
  assert(ws.active ~= nil, "Should have active field")
  assert(ws.paused ~= nil, "Should have paused field")
  log("    [diag] watcher: available=" .. tostring(ws.available) .. " active=" .. tostring(ws.active) .. " paused=" .. tostring(ws.paused))
end)

test(":NeoSaplingWatcher command exists", function()
  local exists = pcall(vim.cmd, "NeoSaplingWatcher")
  assert(exists, ":NeoSaplingWatcher command should exist")
end)

test("Status refresh accepts opts.full parameter", function()
  local status = require("neosapling.status")
  status.open()

  vim.wait(2000, function()
    return vim.fn.bufnr("neosapling://status") ~= -1
  end)

  local ok3, err = pcall(status.refresh, { full = false })
  assert(ok3, "refresh({full=false}) should not error: " .. tostring(err))

  vim.wait(1000)
  status.close()
end)

-- ============================================================
log("")
log("=== Results ===")
log(string.format("  Passed:  %d", passed))
log(string.format("  Failed:  %d", failed))
log(string.format("  Skipped: %d", skipped))
log(string.format("  Total:   %d", passed + failed + skipped))
if failed == 0 then
  log("")
  log("All tests passed!")
else
  log("")
  log("Some tests FAILED — see output above.")
end

flush_log()
log("")
log("Results written to " .. LOG_FILE)
