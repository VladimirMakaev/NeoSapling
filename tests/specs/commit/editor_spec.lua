--- Tests for commit editor module
local editor = require("neosapling.commit.editor")
local staged = require("neosapling.status.staged")
local harness = require("tests.util.sapling_harness")

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
      -- Close any open commit buffers
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local ok, name = pcall(vim.api.nvim_buf_get_name, buf)
        if ok and name:match("neosapling://commit") then
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
end)
