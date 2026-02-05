--- Tests for file action handlers
local file_actions = require("neosapling.actions.file")
local staged = require("neosapling.status.staged")
local harness = require("tests.util.sapling_harness")

describe("neosapling.actions.file", function()
  describe("module", function()
    it("exports stage function", function()
      assert.is_function(file_actions.stage)
    end)

    it("exports unstage function", function()
      assert.is_function(file_actions.unstage)
    end)

    it("exports discard function", function()
      assert.is_function(file_actions.discard)
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
    end)

    describe("stage", function()
      it("stages untracked file (? -> A)", function()
        if not harness.sl_available() then
          pending("sl not available")
          return
        end

        -- Create untracked file
        harness.write_file("newfile.txt", "content")

        local done = false
        local file = { status = "?", path = "newfile.txt" }

        file_actions.stage(file, function()
          done = true
        end)

        vim.wait(2000, function() return done end)

        -- Verify file is now added
        local result = vim.fn.system("cd " .. repo_path .. " && sl status newfile.txt")
        assert.is_not_nil(result:match("A"))
      end)

      it("stages modified file (virtual staging)", function()
        if not harness.sl_available() then
          pending("sl not available")
          return
        end

        -- Modify existing file
        harness.write_file("test.txt", "modified content")

        local file = { status = "M", path = "test.txt" }
        file_actions.stage(file, function() end)

        assert.is_true(staged.is_staged("test.txt"))
      end)
    end)

    describe("unstage", function()
      it("unstages added file (A -> ?)", function()
        if not harness.sl_available() then
          pending("sl not available")
          return
        end

        -- Create and add file
        harness.write_file("newfile.txt", "content")
        vim.fn.system("cd " .. repo_path .. " && sl add newfile.txt")

        local done = false
        local file = { status = "A", path = "newfile.txt" }

        file_actions.unstage(file, function()
          done = true
        end)

        vim.wait(2000, function() return done end)

        -- Verify file is now untracked
        local result = vim.fn.system("cd " .. repo_path .. " && sl status newfile.txt")
        assert.is_not_nil(result:match("%?"))
      end)

      it("unstages virtually staged file", function()
        if not harness.sl_available() then
          pending("sl not available")
          return
        end

        staged.stage("test.txt")
        local file = { status = "M", path = "test.txt" }

        file_actions.unstage(file, function() end)

        assert.is_false(staged.is_staged("test.txt"))
      end)
    end)
  end)
end)
