-- Tests for async process runner
-- lua/neosapling/lib/cli/runner.lua

local runner = require("neosapling.lib.cli.runner")

describe("runner", function()
  describe("basic execution", function()
    it("runs simple command and captures stdout", function()
      local result = nil
      local done = false

      runner.run({ "echo", "hello world" }, {}, function(res)
        result = res
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.equals(0, result.code)
      -- stdout should contain the echoed text
      assert.is_true(#result.stdout > 0)
      assert.is_true(vim.tbl_contains(result.stdout, "hello world") or result.stdout[1] == "hello world")
    end)

    it("returns exit code 0 for successful command", function()
      local result = nil
      local done = false

      runner.run({ "true" }, {}, function(res)
        result = res
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.equals(0, result.code)
    end)

    it("returns non-zero exit code for failed command", function()
      local result = nil
      local done = false

      runner.run({ "false" }, {}, function(res)
        result = res
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.is_true(result.code ~= 0)
    end)

    it("returns non-zero exit code for bash exit 1", function()
      local result = nil
      local done = false

      runner.run({ "bash", "-c", "exit 1" }, {}, function(res)
        result = res
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.equals(1, result.code)
    end)
  end)

  describe("output handling", function()
    it("stdout is array of lines", function()
      local result = nil
      local done = false

      runner.run({ "printf", "line1\nline2\nline3" }, {}, function(res)
        result = res
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.is_table(result.stdout)
      -- The output should be split into lines
      -- Note: depending on how output arrives, we check for expected content
      local combined = table.concat(result.stdout, "\n")
      assert.is_true(combined:find("line1") ~= nil)
      assert.is_true(combined:find("line2") ~= nil)
      assert.is_true(combined:find("line3") ~= nil)
    end)

    it("stderr is array of lines", function()
      local result = nil
      local done = false

      runner.run({ "bash", "-c", "echo error >&2" }, {}, function(res)
        result = res
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.is_table(result.stderr)
      local combined = table.concat(result.stderr, "\n")
      assert.is_true(combined:find("error") ~= nil)
    end)

    it("handles empty output", function()
      local result = nil
      local done = false

      runner.run({ "true" }, {}, function(res)
        result = res
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.is_table(result.stdout)
      assert.is_table(result.stderr)
      -- Even empty output should be an array (may have empty string from accumulator init)
    end)
  end)

  describe("partial line accumulation", function()
    it("properly splits multiline output into array", function()
      local result = nil
      local done = false

      -- Use printf to output multiple lines
      runner.run({ "printf", "a\nb\nc\nd\ne" }, {}, function(res)
        result = res
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      -- Verify all lines are captured
      local combined = table.concat(result.stdout, "\n")
      assert.is_true(combined:find("a") ~= nil)
      assert.is_true(combined:find("b") ~= nil)
      assert.is_true(combined:find("c") ~= nil)
      assert.is_true(combined:find("d") ~= nil)
      assert.is_true(combined:find("e") ~= nil)
    end)

    it("handles output without trailing newline", function()
      local result = nil
      local done = false

      runner.run({ "printf", "no-newline" }, {}, function(res)
        result = res
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      local combined = table.concat(result.stdout, "")
      assert.is_true(combined:find("no%-newline") ~= nil)
    end)

    it("handles output with trailing newline", function()
      local result = nil
      local done = false

      runner.run({ "echo", "with-newline" }, {}, function(res)
        result = res
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      local combined = table.concat(result.stdout, "")
      assert.is_true(combined:find("with%-newline") ~= nil)
    end)
  end)

  describe("async callback", function()
    it("calls callback with result", function()
      local result = nil
      local done = false

      runner.run({ "echo", "test" }, {}, function(res)
        result = res
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.equals(0, result.code)
    end)

    it("result contains code, stdout, stderr fields", function()
      local result = nil
      local done = false

      runner.run({ "echo", "hello" }, {}, function(res)
        result = res
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.is_number(result.code)
      assert.is_table(result.stdout)
      assert.is_table(result.stderr)
    end)
  end)

  describe("cwd option", function()
    it("executes in specified directory", function()
      local result = nil
      local done = false

      runner.run({ "pwd" }, { cwd = "/tmp" }, function(res)
        result = res
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      assert.equals(0, result.code)
      local combined = table.concat(result.stdout, "")
      -- On macOS /tmp is a symlink to /private/tmp
      assert.is_true(combined:find("tmp") ~= nil)
    end)
  end)

  describe("streaming callbacks", function()
    it("on_stdout receives data as it arrives", function()
      local streamed_data = {}
      local result = nil
      local done = false

      runner.run({ "echo", "streamed" }, {
        on_stdout = function(data)
          table.insert(streamed_data, data)
        end,
      }, function(res)
        result = res
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      -- on_stdout should have been called at least once with data
      assert.is_true(#streamed_data > 0)
      local combined = table.concat(streamed_data, "")
      assert.is_true(combined:find("streamed") ~= nil)
    end)

    it("on_stderr receives stderr data", function()
      local streamed_data = {}
      local result = nil
      local done = false

      runner.run({ "bash", "-c", "echo stderr_data >&2" }, {
        on_stderr = function(data)
          table.insert(streamed_data, data)
        end,
      }, function(res)
        result = res
        done = true
      end)

      vim.wait(2000, function()
        return done
      end)

      assert.is_not_nil(result)
      -- on_stderr should have been called with stderr data
      assert.is_true(#streamed_data > 0)
      local combined = table.concat(streamed_data, "")
      assert.is_true(combined:find("stderr_data") ~= nil)
    end)
  end)

  describe("return value", function()
    it("returns SystemObj handle", function()
      local handle = runner.run({ "echo", "test" }, {}, function() end)

      assert.is_not_nil(handle)
      -- SystemObj should have is_closing method
      assert.is_function(handle.is_closing)
    end)
  end)
end)
