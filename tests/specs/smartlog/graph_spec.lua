-- Tests for smartlog graph module (lua/neosapling/smartlog/graph.lua)
-- Phase 8.1: Graph layout is handled by Sapling's ssl output.
-- This module is now an empty backward-compatible stub.

describe("neosapling.smartlog.graph", function()
  it("loads without error", function()
    local graph = require("neosapling.smartlog.graph")
    assert.is_table(graph)
  end)
end)
