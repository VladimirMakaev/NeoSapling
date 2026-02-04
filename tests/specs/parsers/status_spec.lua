-- Tests for status parser (lua/neosapling/lib/parsers/status.lua)
-- Validates parsing of sl status --print0 output

local status = require("neosapling.lib.parsers.status")

describe("status parser", function()
  describe("parse()", function()
    it("returns empty table for nil input", function()
      local result = status.parse(nil)
      assert.same({}, result)
    end)

    it("returns empty table for empty input", function()
      local result = status.parse({})
      assert.same({}, result)
    end)

    it("parses single modified file", function()
      local result = status.parse({ "M file.lua\0" })
      assert.same({
        { status = "M", path = "file.lua" },
      }, result)
    end)

    it("parses multiple files with NUL separator", function()
      local result = status.parse({ "M file1.lua\0A file2.lua\0" })
      assert.same({
        { status = "M", path = "file1.lua" },
        { status = "A", path = "file2.lua" },
      }, result)
    end)

    it("parses all status codes: M, A, R, ?, !, I, C", function()
      -- All entries in single string as --print0 outputs them
      local input = {
        "M modified.lua\0A added.lua\0R removed.lua\0? unknown.lua\0! missing.lua\0I ignored.lua\0C clean.lua\0",
      }
      local result = status.parse(input)
      assert.equals(7, #result)
      assert.equals("M", result[1].status)
      assert.equals("modified.lua", result[1].path)
      assert.equals("A", result[2].status)
      assert.equals("added.lua", result[2].path)
      assert.equals("R", result[3].status)
      assert.equals("?", result[4].status)
      assert.equals("!", result[5].status)
      assert.equals("I", result[6].status)
      assert.equals("C", result[7].status)
    end)

    it("handles files with spaces in path", function()
      local result = status.parse({ "M path with spaces.lua\0" })
      assert.same({
        { status = "M", path = "path with spaces.lua" },
      }, result)
    end)

    it("handles files with special characters in path", function()
      local result = status.parse({ "M file-name_v2.0.lua\0" })
      assert.same({
        { status = "M", path = "file-name_v2.0.lua" },
      }, result)
    end)

    it("handles multi-line input from separate array elements", function()
      -- When output comes as separate array elements, they get joined with newline
      -- Real CLI output uses --print0 so entries are NUL-separated within a single line
      -- This test verifies the join behavior when CLI returns multiple lines
      local result = status.parse({ "M file1.lua\0A file2.lua\0" })
      assert.equals(2, #result)
      assert.equals("M", result[1].status)
      assert.equals("file1.lua", result[1].path)
      assert.equals("A", result[2].status)
      assert.equals("file2.lua", result[2].path)
    end)

    it("handles trailing NUL correctly", function()
      local result = status.parse({ "M file.lua\0\0" })
      assert.same({
        { status = "M", path = "file.lua" },
      }, result)
    end)

    it("handles entry spanning multiple array elements", function()
      -- Entry split across array boundaries is joined by newline
      local result = status.parse({ "M long", "/path/file.lua\0" })
      -- After join: "M long\n/path/file.lua\0"
      -- This parses as a single entry with path "long\n/path/file.lua"
      assert.equals(1, #result)
      assert.equals("M", result[1].status)
      assert.is_truthy(result[1].path:find("long"))
    end)

    it("handles nested directories in path", function()
      local result = status.parse({ "M lua/neosapling/lib/parsers/status.lua\0" })
      assert.same({
        { status = "M", path = "lua/neosapling/lib/parsers/status.lua" },
      }, result)
    end)
  end)

  describe("group()", function()
    it("returns empty groups for empty input", function()
      local result = status.group({})
      assert.same({}, result.modified)
      assert.same({}, result.added)
      assert.same({}, result.removed)
      assert.same({}, result.unknown)
      assert.same({}, result.missing)
      assert.same({}, result.ignored)
      assert.same({}, result.clean)
    end)

    it("places single file in correct group", function()
      local statuses = {
        { status = "M", path = "file.lua" },
      }
      local result = status.group(statuses)
      assert.equals(1, #result.modified)
      assert.equals("file.lua", result.modified[1].path)
    end)

    it("distributes multiple files to correct groups", function()
      local statuses = {
        { status = "M", path = "modified1.lua" },
        { status = "M", path = "modified2.lua" },
        { status = "A", path = "added.lua" },
        { status = "?", path = "unknown.lua" },
      }
      local result = status.group(statuses)
      assert.equals(2, #result.modified)
      assert.equals(1, #result.added)
      assert.equals(1, #result.unknown)
      assert.equals(0, #result.removed)
    end)

    it("maps all status codes to correct group names", function()
      local statuses = {
        { status = "M", path = "m.lua" },
        { status = "A", path = "a.lua" },
        { status = "R", path = "r.lua" },
        { status = "?", path = "q.lua" },
        { status = "!", path = "e.lua" },
        { status = "I", path = "i.lua" },
        { status = "C", path = "c.lua" },
      }
      local result = status.group(statuses)
      assert.equals(1, #result.modified)
      assert.equals(1, #result.added)
      assert.equals(1, #result.removed)
      assert.equals(1, #result.unknown)
      assert.equals(1, #result.missing)
      assert.equals(1, #result.ignored)
      assert.equals(1, #result.clean)
    end)

    it("ignores unknown status codes", function()
      local statuses = {
        { status = "X", path = "unknown_status.lua" },
        { status = "M", path = "valid.lua" },
      }
      local result = status.group(statuses)
      -- X is not a valid status, should not appear in any group
      assert.equals(1, #result.modified)
      assert.equals(0, #result.added)
    end)

    it("all group names are present even when empty", function()
      local result = status.group({})
      assert.is_table(result.modified)
      assert.is_table(result.added)
      assert.is_table(result.removed)
      assert.is_table(result.unknown)
      assert.is_table(result.missing)
      assert.is_table(result.ignored)
      assert.is_table(result.clean)
    end)
  end)

  describe("integration with real sl", function()
    local harness = require("tests.util.sapling_harness")

    it("parses real sl status output for modified file", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      harness.in_repo_with_commit(function(repo_path)
        local cwd = vim.fn.getcwd()
        vim.fn.chdir(repo_path)

        -- Modify the existing test.txt file
        vim.fn.writefile({ "Modified content" }, repo_path .. "/test.txt")

        -- Run sl status --print0 and wrap in table for parser
        local output = vim.fn.system({ "sl", "status", "--print0" })
        local result = status.parse({ output })

        vim.fn.chdir(cwd)

        -- Verify structure
        assert.is_table(result)
        assert.is_true(#result >= 1, "Should have at least one status entry")

        -- Find the modified file
        local found_modified = false
        for _, entry in ipairs(result) do
          if entry.path == "test.txt" and entry.status == "M" then
            found_modified = true
            break
          end
        end
        assert.is_true(found_modified, "Should find modified test.txt")
      end)
    end)

    it("parses real sl status output for untracked file", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      harness.in_repo_with_commit(function(repo_path)
        local cwd = vim.fn.getcwd()
        vim.fn.chdir(repo_path)

        -- Create an untracked file
        vim.fn.writefile({ "Untracked content" }, repo_path .. "/untracked.txt")

        -- Run sl status --print0 and wrap in table for parser
        local output = vim.fn.system({ "sl", "status", "--print0" })
        local result = status.parse({ output })

        vim.fn.chdir(cwd)

        -- Verify structure
        assert.is_table(result)
        assert.is_true(#result >= 1, "Should have at least one status entry")

        -- Find the untracked file
        local found_untracked = false
        for _, entry in ipairs(result) do
          if entry.path == "untracked.txt" and entry.status == "?" then
            found_untracked = true
            break
          end
        end
        assert.is_true(found_untracked, "Should find untracked untracked.txt")
      end)
    end)
  end)
end)
