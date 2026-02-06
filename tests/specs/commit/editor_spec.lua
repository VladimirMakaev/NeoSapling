--- Tests for commit editor module
local editor = require("neosapling.commit.editor")
local staged = require("neosapling.status.staged")
local harness = require("tests.util.sapling_harness")
local status = require("neosapling.status")

describe("neosapling.commit.editor", function()
  describe("module", function()
    it("exports open function", function()
      assert.is_function(editor.open)
    end)
  end)

  describe("with real repo", function()
    local repo_path

    before_each(function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end
      repo_path = harness.create_repo()
      staged.clear()
    end)

    after_each(function()
      harness.cleanup()
      -- Close any open commit/amend buffers
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local ok, name = pcall(vim.api.nvim_buf_get_name, buf)
        if ok and (name:match("neosapling://commit") or name:match("neosapling://amend")) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
    end)

    it("opens commit buffer when files staged", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      -- Create and stage a file
      harness.write_file("newfile.txt", "content")
      vim.fn.system("cd " .. repo_path .. " && sl add newfile.txt")

      editor.open()

      -- Wait for async buffer creation
      vim.wait(1000, function()
        local buf = vim.fn.bufnr("neosapling://commit")
        return buf ~= -1
      end)

      local buf = vim.fn.bufnr("neosapling://commit")
      assert.is_not.equals(-1, buf)
    end)

    it("shows files to commit in buffer", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      -- Create and stage a file
      harness.write_file("newfile.txt", "content")
      vim.fn.system("cd " .. repo_path .. " && sl add newfile.txt")

      editor.open()

      vim.wait(1000, function()
        return vim.fn.bufnr("neosapling://commit") ~= -1
      end)

      local buf = vim.fn.bufnr("neosapling://commit")
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content = table.concat(lines, "\n")

      -- Should contain file reference
      assert.is_not_nil(content:match("newfile.txt"))
    end)

    it("buffer has gitcommit filetype", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      harness.write_file("newfile.txt", "content")
      vim.fn.system("cd " .. repo_path .. " && sl add newfile.txt")

      editor.open()

      vim.wait(1000, function()
        return vim.fn.bufnr("neosapling://commit") ~= -1
      end)

      local buf = vim.fn.bufnr("neosapling://commit")
      local ft = vim.bo[buf].filetype
      assert.equals("gitcommit", ft)
    end)

    it("buffer has acwrite buftype", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      harness.write_file("newfile.txt", "content")
      vim.fn.system("cd " .. repo_path .. " && sl add newfile.txt")

      editor.open()

      vim.wait(1000, function()
        return vim.fn.bufnr("neosapling://commit") ~= -1
      end)

      local buf = vim.fn.bufnr("neosapling://commit")
      local bt = vim.bo[buf].buftype
      assert.equals("acwrite", bt)
    end)

    it("notifies when nothing to commit", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      local notified = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:match("Nothing staged") then
          notified = true
        end
      end

      editor.open()

      vim.wait(500)
      vim.notify = orig_notify

      assert.is_true(notified)
    end)
  end)

  describe("post-commit behavior", function()
    local repo_path

    before_each(function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end
      repo_path = harness.create_repo()
      staged.clear()
    end)

    after_each(function()
      harness.cleanup()
      -- Close any open buffers
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local ok, name = pcall(vim.api.nvim_buf_get_name, buf)
        if ok and (name:match("neosapling://commit") or name:match("neosapling://amend") or name:match("neosapling://status")) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
    end)

    it("calls status.open after successful commit", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      -- Track status.open calls via spy
      local status_open_called = false
      local orig_open = status.open
      status.open = function()
        status_open_called = true
        orig_open()
      end

      -- Create and stage a file
      harness.write_file("testfile.txt", "test content")
      vim.fn.system("cd " .. repo_path .. " && sl add testfile.txt")

      editor.open()

      -- Wait for commit buffer to open
      vim.wait(1000, function()
        return vim.fn.bufnr("neosapling://commit") ~= -1
      end)

      local buf = vim.fn.bufnr("neosapling://commit")
      assert.is_not.equals(-1, buf)

      -- Write commit message and save to trigger commit
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "Test commit message" })
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("write")
      end)

      -- Wait for commit to complete and status.open to be called
      vim.wait(3000, function()
        return status_open_called
      end)

      -- Restore original
      status.open = orig_open

      assert.is_true(status_open_called, "status.open should be called after successful commit")
    end)

    it("shows status buffer after commit completes", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      -- Create and stage a file
      harness.write_file("testfile.txt", "test content")
      vim.fn.system("cd " .. repo_path .. " && sl add testfile.txt")

      editor.open()

      -- Wait for commit buffer to open
      vim.wait(1000, function()
        return vim.fn.bufnr("neosapling://commit") ~= -1
      end)

      local commit_buf = vim.fn.bufnr("neosapling://commit")

      -- Write commit message and save to trigger commit
      vim.api.nvim_buf_set_lines(commit_buf, 0, 1, false, { "Test commit message" })
      vim.api.nvim_buf_call(commit_buf, function()
        vim.cmd("write")
      end)

      -- Wait for status buffer to appear
      vim.wait(3000, function()
        local status_buf = vim.fn.bufnr("neosapling://status")
        return status_buf ~= -1 and vim.fn.bufwinid(status_buf) ~= -1
      end)

      -- Verify status buffer exists and is visible in a window
      local status_buf = vim.fn.bufnr("neosapling://status")
      assert.is_not.equals(-1, status_buf, "Status buffer should exist")
      assert.is_not.equals(-1, vim.fn.bufwinid(status_buf), "Status buffer should be visible in a window")
    end)
  end)

  describe("amend mode", function()
    local repo_path

    before_each(function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end
      repo_path = harness.create_repo()
      staged.clear()

      -- Create an initial commit so there is something to amend
      harness.write_file("initial.txt", "initial content")
      vim.fn.system("cd " .. repo_path .. " && sl add initial.txt && sl commit -m 'Initial commit'")
    end)

    after_each(function()
      harness.cleanup()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local ok, name = pcall(vim.api.nvim_buf_get_name, buf)
        if ok and (name:match("neosapling://commit") or name:match("neosapling://amend") or name:match("neosapling://status")) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
    end)

    it("opens amend buffer with neosapling://amend name", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      editor.open({ amend = true })

      vim.wait(2000, function()
        return vim.fn.bufnr("neosapling://amend") ~= -1
      end)

      local buf = vim.fn.bufnr("neosapling://amend")
      assert.is_not.equals(-1, buf, "Amend buffer should be created")
    end)

    it("pre-fills amend buffer with existing commit message", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      editor.open({ amend = true })

      vim.wait(2000, function()
        return vim.fn.bufnr("neosapling://amend") ~= -1
      end)

      local buf = vim.fn.bufnr("neosapling://amend")
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content = table.concat(lines, "\n")

      -- Should contain the initial commit message
      assert.is_not_nil(content:match("Initial commit"), "Should contain existing commit message")
    end)

    it("amend buffer has gitcommit filetype", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      editor.open({ amend = true })

      vim.wait(2000, function()
        return vim.fn.bufnr("neosapling://amend") ~= -1
      end)

      local buf = vim.fn.bufnr("neosapling://amend")
      assert.equals("gitcommit", vim.bo[buf].filetype)
    end)

    it("amend buffer has acwrite buftype", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      editor.open({ amend = true })

      vim.wait(2000, function()
        return vim.fn.bufnr("neosapling://amend") ~= -1
      end)

      local buf = vim.fn.bufnr("neosapling://amend")
      assert.equals("acwrite", vim.bo[buf].buftype)
    end)

    it("amend buffer shows amend comment text", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      editor.open({ amend = true })

      vim.wait(2000, function()
        return vim.fn.bufnr("neosapling://amend") ~= -1
      end)

      local buf = vim.fn.bufnr("neosapling://amend")
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content = table.concat(lines, "\n")

      assert.is_not_nil(content:match("Amend commit message above"), "Should show amend-specific comment")
    end)

    it("opens amend buffer even with no staged files", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      -- No staged files, but amend should still open
      editor.open({ amend = true })

      vim.wait(2000, function()
        return vim.fn.bufnr("neosapling://amend") ~= -1
      end)

      local buf = vim.fn.bufnr("neosapling://amend")
      assert.is_not.equals(-1, buf, "Amend buffer should open even without staged files")
    end)

    it("amend executes successfully on save", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      editor.open({ amend = true })

      vim.wait(2000, function()
        return vim.fn.bufnr("neosapling://amend") ~= -1
      end)

      local buf = vim.fn.bufnr("neosapling://amend")
      assert.is_not.equals(-1, buf)

      -- Replace the message
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "Amended commit message" })
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("write")
      end)

      -- Wait for amend to complete (buffer should be destroyed)
      vim.wait(3000, function()
        return not vim.api.nvim_buf_is_valid(buf)
      end)

      -- Verify the commit message was amended
      local result = vim.fn.system("cd " .. repo_path .. " && sl log -r . -T '{desc}'")
      assert.is_not_nil(result:match("Amended commit message"), "Commit message should be amended")
    end)
  end)
end)
