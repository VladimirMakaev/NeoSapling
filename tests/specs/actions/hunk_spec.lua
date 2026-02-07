--- Tests for hunk action handlers
local hunk_actions = require("neosapling.actions.hunk")

describe("neosapling.actions.hunk", function()
  describe("module", function()
    it("exports discard function", function()
      assert.is_function(hunk_actions.discard)
    end)

    it("exports find_hunk_at_cursor function", function()
      assert.is_function(hunk_actions.find_hunk_at_cursor)
    end)
  end)

  describe("find_hunk_at_cursor", function()
    it("returns hunk info when cursor is on hunk header", function()
      local mock_hunk = { old_start = 1, old_count = 3, new_start = 1, new_count = 4, lines = {} }
      local mock_file = { path = "test.lua", status = "M" }
      local line_map = {
        [5] = { type = "hunk", hunk = mock_hunk, file = mock_file },
      }
      local result = hunk_actions.find_hunk_at_cursor(line_map, 5)
      assert.is_not_nil(result)
      assert.are.equal(mock_file, result.file)
      assert.are.equal(mock_hunk, result.hunk)
    end)

    it("finds hunk when cursor is on diff_line", function()
      local mock_hunk = { old_start = 1, old_count = 3, new_start = 1, new_count = 4, lines = {} }
      local mock_file = { path = "test.lua", status = "M" }
      local line_map = {
        [5] = { type = "hunk", hunk = mock_hunk, file = mock_file },
        [6] = { type = "diff_line", line = "+added", file = mock_file },
        [7] = { type = "diff_line", line = " context", file = mock_file },
      }
      local result = hunk_actions.find_hunk_at_cursor(line_map, 7)
      assert.is_not_nil(result)
      assert.are.equal(mock_hunk, result.hunk)
      assert.are.equal(mock_file, result.file)
    end)

    it("finds hunk from multiple diff lines away", function()
      local mock_hunk = { old_start = 10, old_count = 5, new_start = 10, new_count = 7, lines = {} }
      local mock_file = { path = "foo.lua", status = "M" }
      local line_map = {
        [10] = { type = "hunk", hunk = mock_hunk, file = mock_file },
        [11] = { type = "diff_line", line = "+new line 1", file = mock_file },
        [12] = { type = "diff_line", line = "+new line 2", file = mock_file },
        [13] = { type = "diff_line", line = " context", file = mock_file },
        [14] = { type = "diff_line", line = "-removed", file = mock_file },
      }
      local result = hunk_actions.find_hunk_at_cursor(line_map, 14)
      assert.is_not_nil(result)
      assert.are.equal(mock_hunk, result.hunk)
    end)

    it("returns nil when not on hunk-related line", function()
      local line_map = {
        [1] = { type = "section", id = "unstaged" },
      }
      local result = hunk_actions.find_hunk_at_cursor(line_map, 1)
      assert.is_nil(result)
    end)

    it("returns nil for empty line map", function()
      local result = hunk_actions.find_hunk_at_cursor({}, 1)
      assert.is_nil(result)
    end)

    it("returns nil when line number has no entry", function()
      local line_map = {
        [1] = { type = "section", id = "unstaged" },
      }
      local result = hunk_actions.find_hunk_at_cursor(line_map, 99)
      assert.is_nil(result)
    end)

    it("stops backward search at non-diff line", function()
      local mock_hunk = { old_start = 1, old_count = 3, new_start = 1, new_count = 4, lines = {} }
      local mock_file = { path = "test.lua", status = "M" }
      local line_map = {
        [5] = { type = "hunk", hunk = mock_hunk, file = mock_file },
        [6] = { type = "diff_line", line = "+added", file = mock_file },
        [7] = { type = "file", file = { path = "other.lua", status = "M" } },
        [8] = { type = "diff_line", line = "+orphan", file = mock_file },
      }
      -- Line 8 is a diff_line but line 7 is a file (non-diff), so backward search stops
      local result = hunk_actions.find_hunk_at_cursor(line_map, 8)
      assert.is_nil(result)
    end)
  end)
end)
