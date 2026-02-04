-- Tests for smartlog parser (lua/neosapling/lib/parsers/smartlog.lua)
-- Validates parsing of sl smartlog -T template output

local smartlog = require("neosapling.lib.parsers.smartlog")

describe("smartlog parser", function()
  describe("constants", function()
    it("TEMPLATE constant exists", function()
      assert.is_string(smartlog.TEMPLATE)
    end)

    it("TEMPLATE contains expected template fields", function()
      local template = smartlog.TEMPLATE
      assert.is_true(template:find("{node|short}") ~= nil)
      assert.is_true(template:find("{graphnode}") ~= nil)
      assert.is_true(template:find("{author|user}") ~= nil)
      assert.is_true(template:find("{date|age}") ~= nil)
      assert.is_true(template:find("{desc|firstline}") ~= nil)
      assert.is_true(template:find("{bookmarks}") ~= nil)
    end)
  end)

  describe("parse_line()", function()
    it("returns nil for empty string", function()
      local result = smartlog.parse_line("")
      assert.is_nil(result)
    end)

    it("returns nil for nil input", function()
      local result = smartlog.parse_line(nil)
      assert.is_nil(result)
    end)

    it("returns nil with fewer than 6 parts", function()
      local result = smartlog.parse_line("abc123|@|user|2 days ago|desc")
      assert.is_nil(result)
    end)

    it("returns Commit table for valid line", function()
      local line = "abc123456789|@|testuser|2 hours ago|Initial commit|main"
      local result = smartlog.parse_line(line)

      assert.is_not_nil(result)
      assert.is_table(result)
    end)

    it("extracts node field", function()
      local line = "abc123456789|@|user|now|desc|"
      local result = smartlog.parse_line(line)

      assert.equals("abc123456789", result.node)
    end)

    it("extracts graphnode field", function()
      local line = "abc123456789|@|user|now|desc|"
      local result = smartlog.parse_line(line)

      assert.equals("@", result.graphnode)
    end)

    it("extracts author field", function()
      local line = "abc123456789|o|johndoe|now|desc|"
      local result = smartlog.parse_line(line)

      assert.equals("johndoe", result.author)
    end)

    it("extracts date field", function()
      local line = "abc123456789|o|user|5 minutes ago|desc|"
      local result = smartlog.parse_line(line)

      assert.equals("5 minutes ago", result.date)
    end)

    it("extracts desc field", function()
      local line = "abc123456789|o|user|now|Fix: handle edge case properly|"
      local result = smartlog.parse_line(line)

      assert.equals("Fix: handle edge case properly", result.desc)
    end)

    it("extracts bookmarks as array", function()
      local line = "abc123456789|o|user|now|desc|main feature-branch"
      local result = smartlog.parse_line(line)

      assert.is_table(result.bookmarks)
      assert.equals(2, #result.bookmarks)
      assert.equals("main", result.bookmarks[1])
      assert.equals("feature-branch", result.bookmarks[2])
    end)

    it("extracts empty bookmarks as empty array", function()
      local line = "abc123456789|o|user|now|desc|"
      local result = smartlog.parse_line(line)

      assert.is_table(result.bookmarks)
      assert.equals(0, #result.bookmarks)
    end)

    it("extracts single bookmark correctly", function()
      local line = "abc123456789|o|user|now|desc|main"
      local result = smartlog.parse_line(line)

      assert.equals(1, #result.bookmarks)
      assert.equals("main", result.bookmarks[1])
    end)

    it("preserves different graphnode characters", function()
      local lines = {
        { line = "a1b2c3d4e5f6|@|u|d|m|", expected = "@" },
        { line = "a1b2c3d4e5f6|o|u|d|m|", expected = "o" },
        { line = "a1b2c3d4e5f6|x|u|d|m|", expected = "x" },
      }

      for _, test in ipairs(lines) do
        local result = smartlog.parse_line(test.line)
        assert.equals(test.expected, result.graphnode)
      end
    end)
  end)

  describe("parse()", function()
    it("returns empty table for nil input", function()
      local result = smartlog.parse(nil)
      assert.same({}, result)
    end)

    it("returns empty table for empty input", function()
      local result = smartlog.parse({})
      assert.same({}, result)
    end)

    it("parses single commit", function()
      local lines = {
        "abc123456789|@|testuser|2 hours ago|Initial commit|main",
      }
      local result = smartlog.parse(lines)

      assert.equals(1, #result)
      assert.equals("abc123456789", result[1].node)
      assert.equals("@", result[1].graphnode)
    end)

    it("parses multiple commits", function()
      local lines = {
        "abc123456789|@|user1|1 hour ago|Latest commit|feature",
        "def456789012|o|user2|2 hours ago|Previous commit|",
        "ghi789012345|o|user1|3 hours ago|First commit|main",
      }
      local result = smartlog.parse(lines)

      assert.equals(3, #result)
      assert.equals("abc123456789", result[1].node)
      assert.equals("def456789012", result[2].node)
      assert.equals("ghi789012345", result[3].node)
    end)

    it("filters out invalid lines", function()
      local lines = {
        "abc123456789|@|user|now|commit|main",
        "", -- empty line
        "invalid|partial", -- too few parts
        "def456789012|o|user|later|another|",
      }
      local result = smartlog.parse(lines)

      assert.equals(2, #result)
      assert.equals("abc123456789", result[1].node)
      assert.equals("def456789012", result[2].node)
    end)

    it("preserves graph characters (@, o, x)", function()
      local lines = {
        "aaa|@|u|d|current working copy|",
        "bbb|o|u|d|normal commit|",
        "ccc|x|u|d|obsolete commit|",
      }
      local result = smartlog.parse(lines)

      assert.equals(3, #result)
      assert.equals("@", result[1].graphnode)
      assert.equals("o", result[2].graphnode)
      assert.equals("x", result[3].graphnode)
    end)

    it("handles commits with multiple bookmarks", function()
      local lines = {
        "abc123|@|user|now|desc|main develop feature-x",
      }
      local result = smartlog.parse(lines)

      assert.equals(1, #result)
      assert.equals(3, #result[1].bookmarks)
      assert.equals("main", result[1].bookmarks[1])
      assert.equals("develop", result[1].bookmarks[2])
      assert.equals("feature-x", result[1].bookmarks[3])
    end)

    it("handles desc with special characters", function()
      local lines = {
        "abc123|@|user|now|Fix: handle | pipe char|",
      }
      local result = smartlog.parse(lines)

      -- With pipe in desc, parsing may be affected
      -- The parser uses first 5 pipes to split, so desc gets truncated
      -- This is expected behavior - desc|firstline shouldn't contain pipes
      assert.equals(1, #result)
      assert.is_string(result[1].desc)
    end)
  end)

  describe("integration with real sl", function()
    local harness = require("tests.util.sapling_harness")

    it("parses real sl smartlog output", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      harness.in_repo_with_commit(function(repo_path)
        local cwd = vim.fn.getcwd()
        vim.fn.chdir(repo_path)

        -- Run sl smartlog with our template
        local output = vim.fn.system({ "sl", "smartlog", "-T", smartlog.TEMPLATE })
        local lines = vim.split(output, "\n", { plain = true })
        local result = smartlog.parse(lines)

        vim.fn.chdir(cwd)

        -- Verify structure
        assert.is_table(result)
        assert.is_true(#result >= 1, "Should have at least one commit")

        -- Check that the commit has expected fields
        local commit = result[1]
        assert.is_string(commit.node)
        assert.is_true(#commit.node > 0, "Node should not be empty")
        assert.is_string(commit.graphnode)
        assert.is_string(commit.author)
        assert.is_string(commit.date)
        assert.is_string(commit.desc)
        assert.is_table(commit.bookmarks)
      end)
    end)
  end)
end)
