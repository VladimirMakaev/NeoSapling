-- Tests for smartlog module (lua/neosapling/smartlog/init.lua)
-- Phase 8.1: Updated for ssl-based rendering pipeline
-- Integration tests using sapling_harness for real sl interaction

describe("neosapling.smartlog integration", function()
  local smartlog
  local harness = require("tests.util.sapling_harness")

  before_each(function()
    smartlog = require("neosapling.smartlog")
  end)

  after_each(function()
    -- Ensure buffer is closed
    pcall(smartlog.close)
  end)

  describe("module structure", function()
    it("exports expected functions", function()
      assert.is_function(smartlog.open)
      assert.is_function(smartlog.refresh)
      assert.is_function(smartlog.close)
      assert.is_function(smartlog.get_line_map)
    end)
  end)

  describe("with real sapling repo", function()
    local original_cwd
    local repo_path
    local ssl_supported = nil

    -- Helper: check if ssl template produces rich output (has hashes)
    local function check_ssl_support()
      if ssl_supported ~= nil then return ssl_supported end
      local result = vim.fn.system({ "sl", "smartlog", "-T", "{ssl}" })
      -- If ssl is supported, output will contain 10-char hex hashes
      ssl_supported = result:match("%x%x%x%x%x%x%x%x%x%x") ~= nil
      return ssl_supported
    end

    -- Helper: wait for line_map to contain commit entries
    local function wait_for_commits(timeout_ms)
      timeout_ms = timeout_ms or 5000
      return vim.wait(timeout_ms, function()
        local lm = smartlog.get_line_map()
        for _, item in pairs(lm) do
          if item.type == "commit" then
            return true
          end
        end
        return false
      end, 100)
    end

    -- Helper: wait for line_map to be non-empty (any type)
    local function wait_for_render(timeout_ms)
      timeout_ms = timeout_ms or 5000
      return vim.wait(timeout_ms, function()
        local buf = vim.fn.bufnr("neosapling://smartlog")
        if buf == -1 then return false end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        -- Buffer has content beyond the default empty line
        return #lines > 0 and (lines[1] ~= "" or #lines > 1)
      end, 100)
    end

    before_each(function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      -- Store original working directory
      original_cwd = vim.fn.getcwd()

      -- Create test repo with initial commit
      repo_path = harness.create_temp_repo()
      harness.with_initial_commit(repo_path)
      vim.fn.chdir(repo_path)

      -- Create additional commits for testing
      vim.fn.writefile({ "modified content" }, repo_path .. "/test.txt")
      vim.fn.system({ "sl", "commit", "-m", "Second commit" })

      -- Setup neosapling before each integration test
      local neosapling = require("neosapling")
      neosapling.setup({})
    end)

    after_each(function()
      pcall(smartlog.close)

      -- Restore original working directory
      if original_cwd then
        vim.fn.chdir(original_cwd)
      end

      -- Clean up temp repo
      if repo_path then
        vim.fn.delete(repo_path, "rf")
      end
    end)

    it("opens buffer and renders content", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      smartlog.open()

      -- Wait for buffer to have content (ssl output rendered)
      local rendered = wait_for_render(5000)
      assert.is_true(rendered, "Buffer should render content")
    end)

    it("closes buffer cleanly", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      smartlog.open()
      smartlog.close()

      local line_map = smartlog.get_line_map()
      assert.are.same({}, line_map)
    end)

    it("creates neosapling://smartlog buffer", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      smartlog.open()

      local buf = vim.fn.bufnr("neosapling://smartlog")
      assert.is_true(buf ~= -1, "Buffer should exist")
    end)

    it("refresh updates buffer content", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      smartlog.open()

      -- Wait for initial render
      wait_for_render(5000)

      -- Refresh again
      smartlog.refresh()

      -- Wait for refresh to complete (buffer still has content)
      local rendered = wait_for_render(5000)
      assert.is_true(rendered, "Should have content after refresh")
    end)

    -- The following tests require ssl template support (internal Sapling builds)
    -- OSS Sapling's {ssl} template doesn't produce rich output

    it("line map contains commit entries with ssl support", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end
      if not check_ssl_support() then
        pending("ssl template not supported (OSS Sapling)")
        return
      end

      smartlog.open()

      local found = wait_for_commits(5000)
      assert.is_true(found, "Should have commits in line map")

      local line_map = smartlog.get_line_map()
      local has_commit = false
      for lnum, item in pairs(line_map) do
        assert.is_number(lnum)
        assert.is_table(item)
        assert.truthy(
          item.type == "commit" or item.type == "message",
          "Expected type 'commit' or 'message', got '" .. tostring(item.type) .. "'"
        )
        if item.type == "commit" then
          has_commit = true
          assert.is_table(item.commit, "Commit-type items should have commit table")
          assert.is_string(item.commit.node, "Commit should have node string")
          assert.equals(10, #item.commit.node, "Hash should be 10 chars, got " .. #item.commit.node)
        end
        if item.type == "message" then
          assert.is_table(item.commit, "Message-type items should reference a commit")
        end
      end
      assert.is_true(has_commit, "Should have at least one commit-type entry")
    end)

    it("positions cursor at current commit on open", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end
      if not check_ssl_support() then
        pending("ssl template not supported (OSS Sapling)")
        return
      end

      smartlog.open()

      local found = wait_for_commits(5000)
      assert.is_true(found, "Should find commits")

      local cursor_line = vim.fn.line(".")
      local line_map = smartlog.get_line_map()
      local item = line_map[cursor_line]
      assert.truthy(item, "Cursor should be on a mapped line (line " .. cursor_line .. ")")
      assert.truthy(
        item.type == "commit" or item.type == "message",
        "Cursor should be on commit-related line"
      )
    end)

    it("line map includes message type entries", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end
      if not check_ssl_support() then
        pending("ssl template not supported (OSS Sapling)")
        return
      end

      smartlog.open()

      local found = wait_for_commits(5000)
      assert.is_true(found, "Should find commits")

      local line_map = smartlog.get_line_map()
      local has_message = false
      for _, item in pairs(line_map) do
        if item.type == "message" then
          has_message = true
          break
        end
      end
      assert.is_true(has_message, "Should have at least one 'message' type entry (2-line draft format)")
    end)

    it("buffer contains ssl output with hashes", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end
      if not check_ssl_support() then
        pending("ssl template not supported (OSS Sapling)")
        return
      end

      smartlog.open()

      local found = wait_for_commits(5000)
      assert.is_true(found, "Should find commits")

      local buf = vim.fn.bufnr("neosapling://smartlog")
      assert.is_true(buf ~= -1, "Buffer should exist")
      local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.is_true(#buf_lines > 0, "Buffer should have content")

      local has_hash = false
      for _, line in ipairs(buf_lines) do
        if line:match("%x%x%x%x%x%x%x%x%x%x") then
          has_hash = true
          break
        end
      end
      assert.is_true(has_hash, "Buffer should contain commit hashes from ssl output")
    end)
  end)
end)
