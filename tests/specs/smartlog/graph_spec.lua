-- Tests for smartlog graph module (lua/neosapling/smartlog/graph.lua)
-- Validates column assignment and prefix building for graph rendering

describe("neosapling.smartlog.graph", function()
  local graph

  before_each(function()
    graph = require("neosapling.smartlog.graph")
  end)

  describe("assign_columns", function()
    it("assigns all commits to column 0 in v1", function()
      local commits = {
        { node = "abc123", graphnode = "@", p1node = "def456" },
        { node = "def456", graphnode = "o", p1node = "ghi789" },
        { node = "ghi789", graphnode = "o", p1node = nil },
      }

      local index, max_cols = graph.assign_columns(commits)

      assert.are.equal(0, index["abc123"])
      assert.are.equal(0, index["def456"])
      assert.are.equal(0, index["ghi789"])
      assert.are.equal(1, max_cols)
    end)

    it("handles empty commit list", function()
      local index, max_cols = graph.assign_columns({})

      assert.are.same({}, index)
      assert.are.equal(1, max_cols)
    end)

    it("handles single commit", function()
      local commits = {
        { node = "abc123", graphnode = "@", p1node = nil },
      }

      local index, max_cols = graph.assign_columns(commits)

      assert.are.equal(0, index["abc123"])
      assert.are.equal(1, max_cols)
    end)

    it("handles commits with mixed graphnode types", function()
      local commits = {
        { node = "abc123", graphnode = "@", p1node = "def456" },
        { node = "def456", graphnode = "x", p1node = "ghi789" },
        { node = "ghi789", graphnode = "o", p1node = nil },
      }

      local index, max_cols = graph.assign_columns(commits)

      -- All in same column for v1
      assert.are.equal(0, index["abc123"])
      assert.are.equal(0, index["def456"])
      assert.are.equal(0, index["ghi789"])
    end)
  end)

  describe("build_prefix", function()
    it("returns consistent indent", function()
      local commit = { node = "abc123", graphnode = "@" }
      local prefix = graph.build_prefix(commit, {}, { ["abc123"] = 0 })

      assert.are.equal("  ", prefix)
    end)

    it("returns same prefix regardless of graphnode type", function()
      local commits = {
        { node = "a", graphnode = "@" },
        { node = "b", graphnode = "o" },
        { node = "c", graphnode = "x" },
      }
      local index = { a = 0, b = 0, c = 0 }

      for _, commit in ipairs(commits) do
        local prefix = graph.build_prefix(commit, {}, index)
        assert.are.equal("  ", prefix)
      end
    end)

    it("returns 2-space prefix for any commit", function()
      local commit = { node = "test123", graphnode = "o" }
      local prefix = graph.build_prefix(commit, {}, { test123 = 0 })

      assert.are.equal(2, #prefix)
      assert.are.equal("  ", prefix)
    end)

    it("handles missing commit in index gracefully", function()
      local commit = { node = "missing", graphnode = "o" }
      local prefix = graph.build_prefix(commit, {}, {})

      -- Should still return consistent prefix
      assert.are.equal("  ", prefix)
    end)
  end)
end)
