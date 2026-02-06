-- Tests for smartlog components module (lua/neosapling/smartlog/components.lua)
-- Validates component tree building and line map construction

describe("neosapling.smartlog.components", function()
  local components

  before_each(function()
    components = require("neosapling.smartlog.components")
  end)

  describe("build", function()
    it("creates header and empty message for no commits", function()
      local tree, line_map = components.build({ commits = {} })

      assert.truthy(tree)
      assert.are.same({}, line_map) -- No commits to map
    end)

    it("creates tree with header as first child", function()
      local tree, _ = components.build({ commits = {} })

      assert.truthy(tree.children)
      assert.is_true(#tree.children >= 1, "Should have at least header")
    end)

    it("creates line map entries for commits", function()
      local commits = {
        {
          node = "abc123456789",
          graphnode = "@",
          author = "testuser",
          date = "5m",
          desc = "Test commit",
          bookmarks = {},
          p1node = nil,
        },
        {
          node = "def456789012",
          graphnode = "o",
          author = "testuser",
          date = "10m",
          desc = "Second commit",
          bookmarks = { "feature" },
          p1node = nil,
        },
      }

      local tree, line_map = components.build({ commits = commits })

      -- Line 1: header, Line 2: empty, Lines 3-4: commits
      assert.truthy(line_map[3])
      assert.are.equal("commit", line_map[3].type)
      assert.are.equal("abc123456789", line_map[3].commit.node)

      assert.truthy(line_map[4])
      assert.are.equal("commit", line_map[4].type)
      assert.are.equal("def456789012", line_map[4].commit.node)
    end)

    it("handles commits with bookmarks", function()
      local commits = {
        {
          node = "abc123",
          graphnode = "@",
          author = "user",
          date = "5m",
          desc = "Test",
          bookmarks = { "main", "feature" },
          p1node = nil,
        },
      }

      local tree, line_map = components.build({ commits = commits })

      assert.truthy(tree)
      assert.truthy(line_map[3])
    end)

    it("preserves commit reference in line map", function()
      local original_commit = {
        node = "test123456",
        graphnode = "@",
        author = "me",
        date = "now",
        desc = "My commit",
        bookmarks = { "main" },
        p1node = "parent",
      }

      local _, line_map = components.build({ commits = { original_commit } })

      local item = line_map[3]
      assert.truthy(item)
      assert.are.equal(original_commit.node, item.commit.node)
      assert.are.equal(original_commit.desc, item.commit.desc)
      assert.are.equal(original_commit.p1node, item.commit.p1node)
    end)

    it("handles nil commits gracefully", function()
      local tree, line_map = components.build({ commits = nil })

      assert.truthy(tree)
      assert.are.same({}, line_map)
    end)

    it("handles empty data table", function()
      local tree, line_map = components.build({})

      assert.truthy(tree)
      assert.are.same({}, line_map)
    end)

    it("assigns correct line numbers sequentially", function()
      local commits = {
        { node = "a", graphnode = "@", author = "u", date = "d", desc = "1", bookmarks = {} },
        { node = "b", graphnode = "o", author = "u", date = "d", desc = "2", bookmarks = {} },
        { node = "c", graphnode = "o", author = "u", date = "d", desc = "3", bookmarks = {} },
      }

      local _, line_map = components.build({ commits = commits })

      -- Line 1: header, Line 2: empty, Lines 3-5: commits
      assert.are.equal("a", line_map[3].commit.node)
      assert.are.equal("b", line_map[4].commit.node)
      assert.are.equal("c", line_map[5].commit.node)
    end)
  end)
end)
