-- Tests for context module (lua/neosapling/status/context.lua)
-- Validates line-to-item context mapping for cursor-aware actions

local context = require("neosapling.status.context")

describe("context module", function()
  describe("get_item_at_line()", function()
    it("returns nil for empty line map", function()
      assert.is_nil(context.get_item_at_line({}, 1))
    end)

    it("returns nil for unmapped line", function()
      local line_map = {
        [1] = { type = "section", id = "test" },
      }

      assert.is_nil(context.get_item_at_line(line_map, 99))
    end)

    it("returns item for mapped line", function()
      local line_map = {
        [1] = { type = "section", id = "untracked" },
      }

      local item = context.get_item_at_line(line_map, 1)
      assert.is_not_nil(item)
    end)

    it("returns section item with correct type", function()
      local line_map = {
        [1] = { type = "section", id = "untracked" },
      }

      local item = context.get_item_at_line(line_map, 1)
      assert.equals("section", item.type)
    end)

    it("returns section item with correct id", function()
      local line_map = {
        [1] = { type = "section", id = "untracked" },
      }

      local item = context.get_item_at_line(line_map, 1)
      assert.equals("untracked", item.id)
    end)

    it("returns file item with correct type and path", function()
      local line_map = {
        [2] = { type = "file", path = "test.lua", section = "unstaged" },
      }

      local item = context.get_item_at_line(line_map, 2)
      assert.equals("file", item.type)
      assert.equals("test.lua", item.path)
    end)

    it("returns file item with section context", function()
      local line_map = {
        [2] = { type = "file", path = "test.lua", section = "unstaged" },
      }

      local item = context.get_item_at_line(line_map, 2)
      assert.equals("unstaged", item.section)
    end)

    it("returns commit item with correct type", function()
      local commit_data = {
        node = "abc123",
        graphnode = "@",
        author = "user",
        date = "1h ago",
        desc = "Test commit",
      }
      local line_map = {
        [5] = { type = "commit", commit = commit_data },
      }

      local item = context.get_item_at_line(line_map, 5)
      assert.equals("commit", item.type)
      assert.equals("abc123", item.commit.node)
    end)

    it("returns bookmark item with correct type", function()
      local bookmark_data = {
        name = "main",
        node = "abc123def456",
      }
      local line_map = {
        [8] = { type = "bookmark", bookmark = bookmark_data },
      }

      local item = context.get_item_at_line(line_map, 8)
      assert.equals("bookmark", item.type)
      assert.equals("main", item.bookmark.name)
    end)

    it("returns hunk item with correct type", function()
      local hunk_data = {
        old_start = 1,
        old_count = 5,
        new_start = 1,
        new_count = 7,
        lines = { "+added line", "-removed line" },
      }
      local file_data = { path = "test.lua" }
      local line_map = {
        [10] = { type = "hunk", hunk = hunk_data, file = file_data, section = "unstaged" },
      }

      local item = context.get_item_at_line(line_map, 10)
      assert.equals("hunk", item.type)
      assert.equals(1, item.hunk.old_start)
    end)

    it("handles multiple items in line map", function()
      local line_map = {
        [1] = { type = "section", id = "untracked" },
        [2] = { type = "file", path = "file1.lua" },
        [3] = { type = "file", path = "file2.lua" },
        [5] = { type = "section", id = "smartlog" },
        [6] = { type = "commit", commit = { node = "abc" } },
      }

      assert.equals("section", context.get_item_at_line(line_map, 1).type)
      assert.equals("file1.lua", context.get_item_at_line(line_map, 2).path)
      assert.equals("file2.lua", context.get_item_at_line(line_map, 3).path)
      assert.is_nil(context.get_item_at_line(line_map, 4)) -- No item at line 4
      assert.equals("section", context.get_item_at_line(line_map, 5).type)
      assert.equals("commit", context.get_item_at_line(line_map, 6).type)
    end)

    it("preserves file object reference", function()
      local file_obj = { status = "M", path = "modified.lua" }
      local line_map = {
        [3] = { type = "file", file = file_obj, section = "unstaged" },
      }

      local item = context.get_item_at_line(line_map, 3)
      assert.equals(file_obj, item.file)
    end)

    it("handles sparse line map (non-consecutive keys)", function()
      local line_map = {
        [1] = { type = "section", id = "header" },
        [5] = { type = "file", path = "a.lua" },
        [10] = { type = "file", path = "b.lua" },
        [100] = { type = "section", id = "footer" },
      }

      assert.is_nil(context.get_item_at_line(line_map, 2))
      assert.is_nil(context.get_item_at_line(line_map, 50))
      assert.equals("a.lua", context.get_item_at_line(line_map, 5).path)
      assert.equals("footer", context.get_item_at_line(line_map, 100).id)
    end)
  end)
end)
