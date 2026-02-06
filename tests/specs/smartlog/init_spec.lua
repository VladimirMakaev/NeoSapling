-- Tests for smartlog module (lua/neosapling/smartlog/init.lua)
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

    it("opens buffer with commits", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      local neosapling = require("neosapling")
      neosapling.setup({})

      smartlog.open()

      -- Wait for async refresh
      vim.wait(2000, function()
        local line_map = smartlog.get_line_map()
        for _, item in pairs(line_map) do
          if item.type == "commit" then
            return true
          end
        end
        return false
      end)

      local line_map = smartlog.get_line_map()
      local has_commits = false
      for _, item in pairs(line_map) do
        if item.type == "commit" then
          has_commits = true
          break
        end
      end

      assert.is_true(has_commits, "Should have commit entries in line map")
    end)

    it("closes buffer cleanly", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      local neosapling = require("neosapling")
      neosapling.setup({})

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

      local neosapling = require("neosapling")
      neosapling.setup({})

      smartlog.open()

      local buf = vim.fn.bufnr("neosapling://smartlog")
      assert.is_true(buf ~= -1, "Buffer should exist")
    end)

    it("refresh updates line map", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      local neosapling = require("neosapling")
      neosapling.setup({})

      smartlog.open()

      -- Wait for initial refresh
      vim.wait(2000, function()
        local line_map = smartlog.get_line_map()
        for _, item in pairs(line_map) do
          if item.type == "commit" then
            return true
          end
        end
        return false
      end)

      local initial_map = smartlog.get_line_map()
      local initial_count = 0
      for _ in pairs(initial_map) do
        initial_count = initial_count + 1
      end

      -- Refresh again
      smartlog.refresh()

      vim.wait(2000, function()
        local line_map = smartlog.get_line_map()
        local count = 0
        for _ in pairs(line_map) do
          count = count + 1
        end
        return count > 0
      end)

      local refreshed_map = smartlog.get_line_map()
      local refreshed_count = 0
      for _ in pairs(refreshed_map) do
        refreshed_count = refreshed_count + 1
      end

      assert.is_true(refreshed_count > 0, "Should have commits after refresh")
    end)

    it("line map contains commit type items", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      local neosapling = require("neosapling")
      neosapling.setup({})

      smartlog.open()

      vim.wait(2000, function()
        local line_map = smartlog.get_line_map()
        for _, item in pairs(line_map) do
          if item.type == "commit" then
            return true
          end
        end
        return false
      end)

      local line_map = smartlog.get_line_map()

      for lnum, item in pairs(line_map) do
        assert.is_number(lnum)
        assert.is_table(item)
        assert.are.equal("commit", item.type)
        assert.is_table(item.commit)
        assert.is_string(item.commit.node)
      end
    end)
  end)
end)
