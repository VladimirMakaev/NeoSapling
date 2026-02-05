-- Tests for bookmarks parser (lua/neosapling/lib/parsers/bookmarks.lua)
-- Validates parsing of sl bookmark -T template output

local bookmarks = require("neosapling.lib.parsers.bookmarks")

describe("bookmarks parser", function()
  describe("constants", function()
    it("TEMPLATE constant exists", function()
      assert.is_string(bookmarks.TEMPLATE)
    end)

    it("TEMPLATE contains expected template fields", function()
      local template = bookmarks.TEMPLATE
      assert.is_true(template:find("bookmark") ~= nil)
      assert.is_true(template:find("node") ~= nil)
    end)

    it("TEMPLATE uses pipe separator", function()
      local template = bookmarks.TEMPLATE
      assert.is_true(template:find("|") ~= nil)
    end)
  end)

  describe("parse_line()", function()
    it("returns nil for nil input", function()
      local result = bookmarks.parse_line(nil)
      assert.is_nil(result)
    end)

    it("returns nil for empty string", function()
      local result = bookmarks.parse_line("")
      assert.is_nil(result)
    end)

    it("returns nil for malformed line without separator", function()
      local result = bookmarks.parse_line("nobookmarkhere")
      assert.is_nil(result)
    end)

    it("returns nil for line with only one part", function()
      local result = bookmarks.parse_line("onlyname")
      assert.is_nil(result)
    end)

    it("parses valid bookmark line", function()
      local line = "main|abc123def456"
      local result = bookmarks.parse_line(line)

      assert.is_not_nil(result)
      assert.is_table(result)
    end)

    it("extracts name field", function()
      local line = "main|abc123def456"
      local result = bookmarks.parse_line(line)

      assert.equals("main", result.name)
    end)

    it("extracts node field", function()
      local line = "main|abc123def456"
      local result = bookmarks.parse_line(line)

      assert.equals("abc123def456", result.node)
    end)

    it("handles bookmark names with hyphens", function()
      local line = "feature-branch|abc123def456"
      local result = bookmarks.parse_line(line)

      assert.equals("feature-branch", result.name)
      assert.equals("abc123def456", result.node)
    end)

    it("handles bookmark names with underscores", function()
      local line = "my_feature|def456abc789"
      local result = bookmarks.parse_line(line)

      assert.equals("my_feature", result.name)
      assert.equals("def456abc789", result.node)
    end)

    it("handles bookmark names with dots", function()
      local line = "release.v1.0|ghi789abc012"
      local result = bookmarks.parse_line(line)

      assert.equals("release.v1.0", result.name)
      assert.equals("ghi789abc012", result.node)
    end)
  end)

  describe("parse()", function()
    it("returns empty array for nil input", function()
      local result = bookmarks.parse(nil)
      assert.same({}, result)
    end)

    it("returns empty array for empty input", function()
      local result = bookmarks.parse({})
      assert.same({}, result)
    end)

    it("parses single bookmark", function()
      local lines = {
        "main|abc123def456",
      }
      local result = bookmarks.parse(lines)

      assert.equals(1, #result)
      assert.equals("main", result[1].name)
      assert.equals("abc123def456", result[1].node)
    end)

    it("parses multiple bookmarks", function()
      local lines = {
        "main|abc123def456",
        "feature|def456abc789",
        "develop|ghi789abc012",
      }
      local result = bookmarks.parse(lines)

      assert.equals(3, #result)
      assert.equals("main", result[1].name)
      assert.equals("feature", result[2].name)
      assert.equals("develop", result[3].name)
    end)

    it("filters out invalid lines", function()
      local lines = {
        "main|abc123def456",
        "",
        "invalid",
        "feature|def456abc789",
      }
      local result = bookmarks.parse(lines)

      assert.equals(2, #result)
      assert.equals("main", result[1].name)
      assert.equals("feature", result[2].name)
    end)

    it("preserves order of bookmarks", function()
      local lines = {
        "zebra|aaa111bbb222",
        "alpha|bbb222ccc333",
        "middle|ccc333ddd444",
      }
      local result = bookmarks.parse(lines)

      assert.equals("zebra", result[1].name)
      assert.equals("alpha", result[2].name)
      assert.equals("middle", result[3].name)
    end)
  end)

  describe("integration with real sl", function()
    local harness = require("tests.util.sapling_harness")

    it("parses real sl bookmark output", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      harness.in_repo_with_commit(function(repo_path)
        local cwd = vim.fn.getcwd()
        vim.fn.chdir(repo_path)

        -- Create a bookmark
        vim.fn.system({ "sl", "bookmark", "test-bookmark" })

        -- Run sl bookmark with our template
        local output = vim.fn.system({ "sl", "bookmark", "-T", bookmarks.TEMPLATE })
        local lines = vim.split(output, "\n", { plain = true })
        local result = bookmarks.parse(lines)

        vim.fn.chdir(cwd)

        -- Verify structure
        assert.is_table(result)
        assert.is_true(#result >= 1, "Should have at least one bookmark")

        -- Check that the bookmark has expected fields
        local found_bookmark = false
        for _, bookmark in ipairs(result) do
          if bookmark.name == "test-bookmark" then
            found_bookmark = true
            assert.is_string(bookmark.node)
            assert.is_true(#bookmark.node > 0, "Node should not be empty")
          end
        end
        assert.is_true(found_bookmark, "Should find test-bookmark")
      end)
    end)
  end)
end)
