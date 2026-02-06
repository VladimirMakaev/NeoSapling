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

  describe("graph prefix handling", function()
    it("parse_line strips graph prefix from node field", function()
      local line = "  o  abc123456789|o|user|now|desc|"
      local result = smartlog.parse_line(line)

      assert.is_not_nil(result)
      assert.equals("abc123456789", result.node)
      assert.equals("o", result.graphnode)
    end)

    it("parse_line strips @ graph prefix", function()
      local line = "  @  abc123456789|@|user|now|Current commit|main"
      local result = smartlog.parse_line(line)

      assert.is_not_nil(result)
      assert.equals("abc123456789", result.node)
      assert.equals("@", result.graphnode)
      assert.equals("main", result.bookmarks[1])
    end)

    it("parse_line handles clean input (no graph prefix) unchanged", function()
      local line = "abc123456789|o|user|now|desc|"
      local result = smartlog.parse_line(line)

      assert.is_not_nil(result)
      assert.equals("abc123456789", result.node)
    end)

    it("parse_line_extended strips graph prefix", function()
      local line = "  o  abc123456789|o|user|5m|Commit msg|main|def456789012|000000000000"
      local result = smartlog.parse_line_extended(line)

      assert.is_not_nil(result)
      assert.equals("abc123456789", result.node)
      assert.equals("def456789012", result.p1node)
      assert.is_nil(result.p2node)
    end)

    it("parse_line_extended strips @ graph prefix with full fields", function()
      local line = "  @  abc123456789|@|user|now|desc||def456789012|ghi789012345"
      local result = smartlog.parse_line_extended(line)

      assert.is_not_nil(result)
      assert.equals("abc123456789", result.node)
      assert.equals("@", result.graphnode)
    end)

    it("parse_line handles graph-only line (no hash) gracefully", function()
      local result1 = smartlog.parse_line("  |  ")
      assert.is_nil(result1)

      local result2 = smartlog.parse_line("  |")
      assert.is_nil(result2)
    end)
  end)

  describe("extended parsing", function()
    describe("TEMPLATE_EXTENDED", function()
      it("includes p1node and p2node", function()
        assert.truthy(smartlog.TEMPLATE_EXTENDED:find("p1node"))
        assert.truthy(smartlog.TEMPLATE_EXTENDED:find("p2node"))
      end)
    end)

    describe("parse_line_extended", function()
      it("parses commit with parent", function()
        local line = "abc123456789|@|user|5 minutes ago|Test commit|main|def456789012|000000000000"
        local commit = smartlog.parse_line_extended(line)

        assert.are.equal("abc123456789", commit.node)
        assert.are.equal("@", commit.graphnode)
        assert.are.equal("user", commit.author)
        assert.are.equal("5 minutes ago", commit.date)
        assert.are.equal("Test commit", commit.desc)
        assert.are.same({"main"}, commit.bookmarks)
        assert.are.equal("def456789012", commit.p1node)
        assert.is_nil(commit.p2node) -- zeros converted to nil
      end)

      it("parses root commit (no parent)", function()
        local line = "abc123456789|o|user|1 day ago|Initial commit||000000000000|000000000000"
        local commit = smartlog.parse_line_extended(line)

        assert.is_nil(commit.p1node)
        assert.is_nil(commit.p2node)
      end)

      it("parses merge commit (two parents)", function()
        local line = "abc123456789|o|user|2 hours ago|Merge commit||def456789012|ghi789012345"
        local commit = smartlog.parse_line_extended(line)

        assert.are.equal("def456789012", commit.p1node)
        assert.are.equal("ghi789012345", commit.p2node)
      end)

      it("returns nil for empty line", function()
        assert.is_nil(smartlog.parse_line_extended(""))
        assert.is_nil(smartlog.parse_line_extended(nil))
      end)

      it("returns nil for malformed line (too few fields)", function()
        assert.is_nil(smartlog.parse_line_extended("abc|@|user"))
      end)
    end)

    describe("parse_extended", function()
      it("parses multiple commits", function()
        local lines = {
          "abc123456789|@|user|5m|Commit 1|main|def456789012|000000000000",
          "def456789012|o|user|10m|Commit 2||000000000000|000000000000",
        }
        local commits = smartlog.parse_extended(lines)

        assert.are.equal(2, #commits)
        assert.are.equal("abc123456789", commits[1].node)
        assert.are.equal("def456789012", commits[1].p1node)
        assert.are.equal("def456789012", commits[2].node)
        assert.is_nil(commits[2].p1node)
      end)

      it("handles empty input", function()
        assert.are.same({}, smartlog.parse_extended({}))
        assert.are.same({}, smartlog.parse_extended(nil))
      end)

      it("skips malformed lines", function()
        local lines = {
          "abc123456789|@|user|5m|Commit 1|main|def456789012|000000000000",
          "", -- empty line
          "malformed",
          "def456789012|o|user|10m|Commit 2||000000000000|000000000000",
        }
        local commits = smartlog.parse_extended(lines)

        assert.are.equal(2, #commits)
      end)
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
        assert.truthy(commit.node:match("^%x+$"), "Node should be clean hex hash, got: " .. commit.node)
        assert.is_string(commit.graphnode)
        assert.is_string(commit.author)
        assert.is_string(commit.date)
        assert.is_string(commit.desc)
        assert.is_table(commit.bookmarks)
      end)
    end)

    it("produces clean hashes usable by sl diff", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      harness.in_repo_with_commit(function(repo_path)
        local cwd = vim.fn.getcwd()
        vim.fn.chdir(repo_path)

        -- Parse smartlog to get a commit hash
        local sl_output = vim.fn.system({ "sl", "smartlog", "-T", smartlog.TEMPLATE_EXTENDED })
        local sl_lines = vim.split(sl_output, "\n", { plain = true })
        local commits = smartlog.parse_extended(sl_lines)

        assert.is_true(#commits >= 1, "Should have at least one commit")
        local commit = commits[1]

        -- Validate node is clean hex
        assert.truthy(commit.node:match("^%x+$"), "Node should be clean hex, got: " .. tostring(commit.node))

        -- Use the parsed hash to run sl diff (the exact flow that was broken)
        -- Create a change first so diff has output
        vim.fn.writefile({ "Modified for diff test" }, repo_path .. "/test.txt")

        local diff_output = vim.fn.system({ "sl", "diff", "-r", commit.node, "--git" })
        local diff_lines = vim.split(diff_output, "\n", { plain = true })

        -- sl diff should NOT error (shell_error == 0)
        assert.equals(0, vim.v.shell_error, "sl diff should succeed with parsed hash")

        -- Parse diff output
        local diff_parser = require("neosapling.lib.parsers.diff")
        local diffs = diff_parser.parse(diff_lines)
        assert.is_table(diffs)
        assert.is_true(#diffs >= 1, "Should have at least one file diff")

        -- Validate diff structure
        local file_diff = diffs[1]
        assert.is_string(file_diff.from_path)
        assert.is_table(file_diff.hunks)
        assert.is_true(#file_diff.hunks >= 1, "Should have at least one hunk")

        vim.fn.chdir(cwd)
      end)
    end)
  end)
end)
