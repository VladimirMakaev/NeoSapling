-- Tests for diff parser (lua/neosapling/lib/parsers/diff.lua)
-- Validates parsing of sl diff --git output

local diff = require("neosapling.lib.parsers.diff")

describe("diff parser", function()
  describe("constants", function()
    it("DIFF_HEADER pattern exists", function()
      assert.is_string(diff.DIFF_HEADER)
    end)

    it("HUNK_HEADER pattern exists", function()
      assert.is_string(diff.HUNK_HEADER)
    end)
  end)

  describe("parse()", function()
    it("returns empty table for nil input", function()
      local result = diff.parse(nil)
      assert.same({}, result)
    end)

    it("returns empty table for empty input", function()
      local result = diff.parse({})
      assert.same({}, result)
    end)

    it("parses single file diff with one hunk", function()
      local lines = {
        "diff --git a/file.lua b/file.lua",
        "--- a/file.lua",
        "+++ b/file.lua",
        "@@ -1,3 +1,4 @@ function foo()",
        " context line",
        "-removed line",
        "+added line",
        "+new line",
      }
      local result = diff.parse(lines)

      assert.equals(1, #result)
      assert.equals("file.lua", result[1].from_path)
      assert.equals("file.lua", result[1].to_path)
      assert.equals(1, #result[1].hunks)
    end)

    it("extracts from_path and to_path from header", function()
      local lines = {
        "diff --git a/old/path.lua b/new/path.lua",
        "@@ -1 +1 @@",
        "-old",
        "+new",
      }
      local result = diff.parse(lines)

      assert.equals(1, #result)
      assert.equals("old/path.lua", result[1].from_path)
      assert.equals("new/path.lua", result[1].to_path)
    end)

    it("hunk has old_start, old_count, new_start, new_count, header, lines", function()
      local lines = {
        "diff --git a/test.lua b/test.lua",
        "--- a/test.lua",
        "+++ b/test.lua",
        "@@ -10,5 +12,7 @@ function example()",
        " context",
        "-removed",
        "+added",
      }
      local result = diff.parse(lines)

      assert.equals(1, #result)
      local hunk = result[1].hunks[1]
      assert.equals(10, hunk.old_start)
      assert.equals(5, hunk.old_count)
      assert.equals(12, hunk.new_start)
      assert.equals(7, hunk.new_count)
      assert.equals(" function example()", hunk.header)
      assert.is_table(hunk.lines)
    end)

    it("skips --- and +++ lines in hunk content", function()
      local lines = {
        "diff --git a/file.lua b/file.lua",
        "--- a/file.lua",
        "+++ b/file.lua",
        "@@ -1,2 +1,2 @@",
        " context",
        "-old",
        "+new",
      }
      local result = diff.parse(lines)

      local hunk = result[1].hunks[1]
      -- Should have 3 lines: context, -old, +new
      -- Should NOT include --- or +++
      assert.equals(3, #hunk.lines)
      for _, line in ipairs(hunk.lines) do
        assert.is_false(line:match("^%-%-%-") ~= nil)
        assert.is_false(line:match("^%+%+%+") ~= nil)
      end
    end)

    it("parses hunk with missing count (defaults to 1)", function()
      local lines = {
        "diff --git a/file.lua b/file.lua",
        "@@ -5 +5 @@",
        "-single",
        "+replaced",
      }
      local result = diff.parse(lines)

      local hunk = result[1].hunks[1]
      assert.equals(5, hunk.old_start)
      assert.equals(1, hunk.old_count) -- defaulted
      assert.equals(5, hunk.new_start)
      assert.equals(1, hunk.new_count) -- defaulted
    end)

    it("parses multiple files", function()
      local lines = {
        "diff --git a/file1.lua b/file1.lua",
        "@@ -1 +1 @@",
        "-old1",
        "+new1",
        "diff --git a/file2.lua b/file2.lua",
        "@@ -1 +1 @@",
        "-old2",
        "+new2",
      }
      local result = diff.parse(lines)

      assert.equals(2, #result)
      assert.equals("file1.lua", result[1].from_path)
      assert.equals("file2.lua", result[2].from_path)
    end)

    it("parses multiple hunks in single file", function()
      local lines = {
        "diff --git a/file.lua b/file.lua",
        "--- a/file.lua",
        "+++ b/file.lua",
        "@@ -1,3 +1,3 @@ first section",
        " context1",
        "-removed1",
        "+added1",
        "@@ -20,2 +20,3 @@ second section",
        " context2",
        "+new_line1",
        "+new_line2",
      }
      local result = diff.parse(lines)

      assert.equals(1, #result)
      assert.equals(2, #result[1].hunks)

      local hunk1 = result[1].hunks[1]
      assert.equals(1, hunk1.old_start)
      assert.equals(" first section", hunk1.header)

      local hunk2 = result[1].hunks[2]
      assert.equals(20, hunk2.old_start)
      assert.equals(" second section", hunk2.header)
    end)

    it("handles complex multi-file multi-hunk diff", function()
      local lines = {
        "diff --git a/src/main.lua b/src/main.lua",
        "--- a/src/main.lua",
        "+++ b/src/main.lua",
        "@@ -1,5 +1,6 @@",
        " line1",
        " line2",
        "-old line",
        "+new line",
        "+extra line",
        " line4",
        "@@ -50,3 +51,4 @@ function end_section()",
        " end",
        "+-- added comment",
        " return M",
        "diff --git a/tests/test.lua b/tests/test.lua",
        "--- a/tests/test.lua",
        "+++ b/tests/test.lua",
        "@@ -10,2 +10,3 @@",
        " existing",
        "+new test",
      }
      local result = diff.parse(lines)

      assert.equals(2, #result)

      -- First file
      assert.equals("src/main.lua", result[1].from_path)
      assert.equals(2, #result[1].hunks)

      -- Second file
      assert.equals("tests/test.lua", result[2].from_path)
      assert.equals(1, #result[2].hunks)
    end)

    it("preserves hunk line content exactly", function()
      local lines = {
        "diff --git a/file.lua b/file.lua",
        "@@ -1,4 +1,4 @@",
        " context with spaces",
        "-  indented removal",
        "+  indented addition",
        " trailing context",
      }
      local result = diff.parse(lines)

      local hunk = result[1].hunks[1]
      assert.equals(4, #hunk.lines)
      assert.equals(" context with spaces", hunk.lines[1])
      assert.equals("-  indented removal", hunk.lines[2])
      assert.equals("+  indented addition", hunk.lines[3])
      assert.equals(" trailing context", hunk.lines[4])
    end)

    it("handles new file (no from path content)", function()
      local lines = {
        "diff --git a/newfile.lua b/newfile.lua",
        "--- /dev/null",
        "+++ b/newfile.lua",
        "@@ -0,0 +1,3 @@",
        "+line1",
        "+line2",
        "+line3",
      }
      local result = diff.parse(lines)

      assert.equals(1, #result)
      local hunk = result[1].hunks[1]
      assert.equals(0, hunk.old_start)
      assert.equals(0, hunk.old_count)
      assert.equals(1, hunk.new_start)
      assert.equals(3, hunk.new_count)
    end)
  end)

  describe("integration with real sl", function()
    local harness = require("tests.util.sapling_harness")

    it("parses real sl diff output", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      harness.in_repo_with_commit(function(repo_path)
        local cwd = vim.fn.getcwd()
        vim.fn.chdir(repo_path)

        -- Modify the existing test.txt file to create a diff
        vim.fn.writefile({ "Modified content", "New line added" }, repo_path .. "/test.txt")

        -- Run sl diff --git
        local output = vim.fn.system({ "sl", "diff", "--git" })
        local lines = vim.split(output, "\n", { plain = true })
        local result = diff.parse(lines)

        vim.fn.chdir(cwd)

        -- Verify structure
        assert.is_table(result)
        assert.is_true(#result >= 1, "Should have at least one file diff")

        -- Check that the diff has expected structure
        local file_diff = result[1]
        assert.is_string(file_diff.from_path)
        assert.is_string(file_diff.to_path)
        assert.is_table(file_diff.hunks)
        assert.is_true(#file_diff.hunks >= 1, "Should have at least one hunk")

        -- Check hunk structure
        local hunk = file_diff.hunks[1]
        assert.is_number(hunk.old_start)
        assert.is_number(hunk.new_start)
        assert.is_table(hunk.lines)
        assert.is_true(#hunk.lines >= 1, "Hunk should have lines")
      end)
    end)
  end)
end)
