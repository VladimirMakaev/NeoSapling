-- Tests for status module (lua/neosapling/status/init.lua)
-- Integration tests using sapling_harness for real sl interaction

local status = require("neosapling.status")
local harness = require("tests.util.sapling_harness")

describe("status module", function()
  local repo_path
  local original_cwd

  before_each(function()
    if not harness.sl_available() then
      pending("sl not available")
      return
    end

    -- Store original working directory
    original_cwd = vim.fn.getcwd()

    -- Create test repo with some content
    repo_path = harness.create_temp_repo()
    harness.with_initial_commit(repo_path)

    -- Create untracked file
    vim.fn.writefile({ "-- untracked content" }, repo_path .. "/untracked.lua")

    -- Modify tracked file
    vim.fn.writefile({ "-- modified content" }, repo_path .. "/test.txt")

    -- Change to repo directory for sl commands
    vim.fn.chdir(repo_path)
  end)

  after_each(function()
    -- Clean up any open status buffer
    pcall(function() status.close() end)

    -- Restore original working directory
    if original_cwd then
      vim.fn.chdir(original_cwd)
    end

    -- Clean up temp repo
    if repo_path then
      vim.fn.delete(repo_path, "rf")
    end
  end)

  describe("open()", function()
    it("creates neosapling://status buffer", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      status.open()

      local buf = vim.fn.bufnr("neosapling://status")
      assert.is_true(buf ~= -1, "Buffer should exist")
    end)

    it("creates scratch buffer with correct buftype", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      status.open()

      local buf = vim.fn.bufnr("neosapling://status")
      local buftype = vim.api.nvim_buf_get_option(buf, "buftype")
      assert.equals("nofile", buftype)
    end)

    it("creates unlisted buffer", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      status.open()

      local buf = vim.fn.bufnr("neosapling://status")
      local buflisted = vim.api.nvim_buf_get_option(buf, "buflisted")
      assert.is_false(buflisted)
    end)

    it("creates buffer with neosapling filetype", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      status.open()

      local buf = vim.fn.bufnr("neosapling://status")
      local filetype = vim.api.nvim_buf_get_option(buf, "filetype")
      assert.equals("neosapling", filetype)
    end)

    it("reuses existing buffer on second open", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      status.open()
      local buf1 = vim.fn.bufnr("neosapling://status")

      -- Close window but don't destroy buffer
      vim.cmd("close")

      status.open()
      local buf2 = vim.fn.bufnr("neosapling://status")

      assert.equals(buf1, buf2)
    end)
  end)

  describe("refresh()", function()
    it("populates buffer with content", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      status.open()

      -- Wait for async refresh to complete
      vim.wait(2000, function()
        local buf = vim.fn.bufnr("neosapling://status")
        if buf == -1 then return false end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        return #lines > 1
      end)

      local buf = vim.fn.bufnr("neosapling://status")
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.is_true(#lines > 1, "Should have content")
    end)

    it("includes NeoSapling Status header", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      status.open()

      vim.wait(2000, function()
        local buf = vim.fn.bufnr("neosapling://status")
        if buf == -1 then return false end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        return #lines > 1
      end)

      local buf = vim.fn.bufnr("neosapling://status")
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

      local has_header = false
      for _, line in ipairs(lines) do
        if line:match("NeoSapling Status") then
          has_header = true
          break
        end
      end
      assert.is_true(has_header, "Should have NeoSapling Status header")
    end)

    it("shows untracked files", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      status.open()

      vim.wait(2000, function()
        local buf = vim.fn.bufnr("neosapling://status")
        if buf == -1 then return false end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        for _, line in ipairs(lines) do
          if line:match("untracked.lua") then return true end
        end
        return false
      end)

      local buf = vim.fn.bufnr("neosapling://status")
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

      local found_untracked = false
      for _, line in ipairs(lines) do
        if line:match("untracked.lua") then
          found_untracked = true
          break
        end
      end
      assert.is_true(found_untracked, "Should show untracked.lua")
    end)

    it("shows modified files", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      status.open()

      vim.wait(2000, function()
        local buf = vim.fn.bufnr("neosapling://status")
        if buf == -1 then return false end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        for _, line in ipairs(lines) do
          if line:match("test.txt") then return true end
        end
        return false
      end)

      local buf = vim.fn.bufnr("neosapling://status")
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

      local found_modified = false
      for _, line in ipairs(lines) do
        if line:match("test.txt") then
          found_modified = true
          break
        end
      end
      assert.is_true(found_modified, "Should show modified test.txt")
    end)

    it("shows Current Stack with commit", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      status.open()

      vim.wait(2000, function()
        local buf = vim.fn.bufnr("neosapling://status")
        if buf == -1 then return false end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        for _, line in ipairs(lines) do
          if line:match("Current Stack") then return true end
        end
        return false
      end)

      local buf = vim.fn.bufnr("neosapling://status")
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

      local found_stack = false
      for _, line in ipairs(lines) do
        if line:match("Current Stack") then
          found_stack = true
          break
        end
      end
      assert.is_true(found_stack, "Should show Current Stack section")
    end)
  end)

  describe("close()", function()
    it("destroys buffer", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      status.open()
      local buf = vim.fn.bufnr("neosapling://status")
      assert.is_true(buf ~= -1)

      status.close()
      assert.is_false(vim.api.nvim_buf_is_valid(buf))
    end)

    it("handles close when already closed", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      status.open()
      status.close()

      -- Should not error on second close
      assert.has_no.errors(function()
        status.close()
      end)
    end)
  end)

  describe("get_line_map()", function()
    it("returns line map table", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      status.open()

      vim.wait(2000, function()
        local buf = vim.fn.bufnr("neosapling://status")
        if buf == -1 then return false end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        return #lines > 1
      end)

      local line_map = status.get_line_map()
      assert.is_table(line_map)
    end)

    it("contains file items after refresh", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      status.open()

      vim.wait(2000, function()
        local buf = vim.fn.bufnr("neosapling://status")
        if buf == -1 then return false end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        return #lines > 1
      end)

      local line_map = status.get_line_map()

      local file_count = 0
      for _, item in pairs(line_map) do
        if item.type == "file" then
          file_count = file_count + 1
        end
      end
      assert.is_true(file_count >= 1, "Should have at least one file in line_map")
    end)
  end)

  describe("Tab keymap", function()
    it("is buffer-local", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      status.open()

      local buf = vim.fn.bufnr("neosapling://status")
      local keymaps = vim.api.nvim_buf_get_keymap(buf, "n")

      local has_tab = false
      for _, keymap in ipairs(keymaps) do
        if keymap.lhs == "<Tab>" then
          has_tab = true
          break
        end
      end
      assert.is_true(has_tab, "Should have Tab keymap")
    end)
  end)
end)
