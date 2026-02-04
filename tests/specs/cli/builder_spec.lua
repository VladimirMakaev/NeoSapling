-- Tests for CommandBuilder fluent API
-- lua/neosapling/lib/cli/builder.lua

local CommandBuilder = require("neosapling.lib.cli.builder")

describe("CommandBuilder", function()
  local mock_runner

  before_each(function()
    -- Create a mock runner with a run function
    mock_runner = {
      run = function(cmd, opts, on_exit)
        return { is_closing = function() return true end }
      end,
    }
  end)

  describe("new()", function()
    it("creates builder with 'sl' as initial command", function()
      local builder = CommandBuilder:new(mock_runner)
      assert.same({ "sl" }, builder._cmd)
    end)

    it("stores runner reference", function()
      local builder = CommandBuilder:new(mock_runner)
      assert.equals(mock_runner, builder._runner)
    end)
  end)

  describe("arg()", function()
    it("adds single argument to command", function()
      local builder = CommandBuilder:new(mock_runner)
      builder:arg("status")
      assert.same({ "sl", "status" }, builder._cmd)
    end)

    it("converts numbers to strings", function()
      local builder = CommandBuilder:new(mock_runner)
      builder:arg(42)
      assert.same({ "sl", "42" }, builder._cmd)
    end)

    it("returns self for chaining", function()
      local builder = CommandBuilder:new(mock_runner)
      local result = builder:arg("test")
      assert.equals(builder, result)
    end)
  end)

  describe("opt()", function()
    it("adds flag without value", function()
      local builder = CommandBuilder:new(mock_runner)
      builder:opt("--verbose")
      assert.same({ "sl", "--verbose" }, builder._cmd)
    end)

    it("adds flag with value as two elements", function()
      local builder = CommandBuilder:new(mock_runner)
      builder:opt("-r", "HEAD")
      assert.same({ "sl", "-r", "HEAD" }, builder._cmd)
    end)

    it("converts number values to strings", function()
      local builder = CommandBuilder:new(mock_runner)
      builder:opt("-n", 10)
      assert.same({ "sl", "-n", "10" }, builder._cmd)
    end)

    it("returns self for chaining", function()
      local builder = CommandBuilder:new(mock_runner)
      local result = builder:opt("-r", ".")
      assert.equals(builder, result)
    end)
  end)

  describe("subcommand convenience methods", function()
    local subcommands = {
      { method = "status", arg = "status" },
      { method = "diff", arg = "diff" },
      { method = "log", arg = "log" },
      { method = "smartlog", arg = "smartlog" },
      { method = "commit", arg = "commit" },
      { method = "add", arg = "add" },
      { method = "goto_rev", arg = "goto" },
      { method = "amend", arg = "amend" },
      { method = "absorb", arg = "absorb" },
      { method = "rebase", arg = "rebase" },
      { method = "hide", arg = "hide" },
      { method = "unhide", arg = "unhide" },
      { method = "pull", arg = "pull" },
    }

    for _, sub in ipairs(subcommands) do
      it(sub.method .. "() adds '" .. sub.arg .. "'", function()
        local builder = CommandBuilder:new(mock_runner)
        local result = builder[sub.method](builder)
        assert.same({ "sl", sub.arg }, builder._cmd)
        assert.equals(builder, result) -- returns self
      end)
    end
  end)

  describe("flag convenience methods", function()
    it("print0() adds '--print0'", function()
      local builder = CommandBuilder:new(mock_runner)
      local result = builder:print0()
      assert.same({ "sl", "--print0" }, builder._cmd)
      assert.equals(builder, result)
    end)

    it("git_format() adds '--git'", function()
      local builder = CommandBuilder:new(mock_runner)
      local result = builder:git_format()
      assert.same({ "sl", "--git" }, builder._cmd)
      assert.equals(builder, result)
    end)

    it("template(tmpl) adds '-T' and template value", function()
      local builder = CommandBuilder:new(mock_runner)
      local result = builder:template("{node}")
      assert.same({ "sl", "-T", "{node}" }, builder._cmd)
      assert.equals(builder, result)
    end)

    it("rev(revision) adds '-r' and revision", function()
      local builder = CommandBuilder:new(mock_runner)
      local result = builder:rev("HEAD~1")
      assert.same({ "sl", "-r", "HEAD~1" }, builder._cmd)
      assert.equals(builder, result)
    end)

    it("message(msg) adds '-m' and message", function()
      local builder = CommandBuilder:new(mock_runner)
      local result = builder:message("Fix bug")
      assert.same({ "sl", "-m", "Fix bug" }, builder._cmd)
      assert.equals(builder, result)
    end)

    it("interactive() adds '--interactive'", function()
      local builder = CommandBuilder:new(mock_runner)
      local result = builder:interactive()
      assert.same({ "sl", "--interactive" }, builder._cmd)
      assert.equals(builder, result)
    end)

    it("no_edit() adds '--no-edit'", function()
      local builder = CommandBuilder:new(mock_runner)
      local result = builder:no_edit()
      assert.same({ "sl", "--no-edit" }, builder._cmd)
      assert.equals(builder, result)
    end)

    it("dest(d) adds '-d' and destination", function()
      local builder = CommandBuilder:new(mock_runner)
      local result = builder:dest("main")
      assert.same({ "sl", "-d", "main" }, builder._cmd)
      assert.equals(builder, result)
    end)

    it("file(path) adds path", function()
      local builder = CommandBuilder:new(mock_runner)
      local result = builder:file("src/main.lua")
      assert.same({ "sl", "src/main.lua" }, builder._cmd)
      assert.equals(builder, result)
    end)

    it("files(paths) adds all paths", function()
      local builder = CommandBuilder:new(mock_runner)
      local result = builder:files({ "file1.lua", "file2.lua", "file3.lua" })
      assert.same({ "sl", "file1.lua", "file2.lua", "file3.lua" }, builder._cmd)
      assert.equals(builder, result)
    end)
  end)

  describe("chaining", function()
    it("status():print0() produces correct array", function()
      local builder = CommandBuilder:new(mock_runner)
      builder:status():print0()
      assert.same({ "sl", "status", "--print0" }, builder._cmd)
    end)

    it("diff():git_format():rev('.') produces correct array", function()
      local builder = CommandBuilder:new(mock_runner)
      builder:diff():git_format():rev(".")
      assert.same({ "sl", "diff", "--git", "-r", "." }, builder._cmd)
    end)

    it("commit():message('test'):no_edit() produces correct array", function()
      local builder = CommandBuilder:new(mock_runner)
      builder:commit():message("test commit"):no_edit()
      assert.same({ "sl", "commit", "-m", "test commit", "--no-edit" }, builder._cmd)
    end)

    it("rebase():dest('main'):interactive() produces correct array", function()
      local builder = CommandBuilder:new(mock_runner)
      builder:rebase():dest("main"):interactive()
      assert.same({ "sl", "rebase", "-d", "main", "--interactive" }, builder._cmd)
    end)

    it("add():files() with multiple files produces correct array", function()
      local builder = CommandBuilder:new(mock_runner)
      builder:add():files({ "a.lua", "b.lua" })
      assert.same({ "sl", "add", "a.lua", "b.lua" }, builder._cmd)
    end)

    it("log():rev('HEAD'):template('{node}') produces correct array", function()
      local builder = CommandBuilder:new(mock_runner)
      builder:log():rev("HEAD"):template("{node}")
      assert.same({ "sl", "log", "-r", "HEAD", "-T", "{node}" }, builder._cmd)
    end)
  end)

  describe("call()", function()
    it("calls runner.run with accumulated command", function()
      local captured_cmd = nil
      mock_runner.run = function(cmd, opts, on_exit)
        captured_cmd = cmd
        return { is_closing = function() return true end }
      end

      local builder = CommandBuilder:new(mock_runner)
      builder:status():print0():call({}, function() end)

      assert.same({ "sl", "status", "--print0" }, captured_cmd)
    end)

    it("passes options to runner.run", function()
      local captured_opts = nil
      mock_runner.run = function(cmd, opts, on_exit)
        captured_opts = opts
        return { is_closing = function() return true end }
      end

      local builder = CommandBuilder:new(mock_runner)
      builder:status():call({ cwd = "/tmp" }, function() end)

      assert.same({ cwd = "/tmp" }, captured_opts)
    end)
  end)
end)
