--- Tests for virtual staging module
local staged = require("neosapling.status.staged")

describe("neosapling.status.staged", function()
  before_each(function()
    -- Clear staging state before each test
    staged.clear()
  end)

  describe("stage", function()
    it("adds file to staged set", function()
      staged.stage("test.lua")
      assert.is_true(staged.is_staged("test.lua"))
    end)

    it("can stage multiple files", function()
      staged.stage("a.lua")
      staged.stage("b.lua")
      assert.is_true(staged.is_staged("a.lua"))
      assert.is_true(staged.is_staged("b.lua"))
    end)

    it("is idempotent", function()
      staged.stage("test.lua")
      staged.stage("test.lua")
      local files = staged.get_staged()
      local count = 0
      for _, _ in ipairs(files) do
        count = count + 1
      end
      -- File should only appear once
      assert.equals(1, count)
    end)
  end)

  describe("unstage", function()
    it("removes file from staged set", function()
      staged.stage("test.lua")
      staged.unstage("test.lua")
      assert.is_false(staged.is_staged("test.lua"))
    end)

    it("handles unstaging non-staged file", function()
      -- Should not error
      staged.unstage("nonexistent.lua")
      assert.is_false(staged.is_staged("nonexistent.lua"))
    end)
  end)

  describe("is_staged", function()
    it("returns false for non-staged files", function()
      assert.is_false(staged.is_staged("test.lua"))
    end)

    it("returns true for staged files", function()
      staged.stage("test.lua")
      assert.is_true(staged.is_staged("test.lua"))
    end)
  end)

  describe("get_staged", function()
    it("returns empty table when nothing staged", function()
      local files = staged.get_staged()
      assert.equals(0, #files)
    end)

    it("returns all staged files", function()
      staged.stage("a.lua")
      staged.stage("b.lua")
      local files = staged.get_staged()
      assert.equals(2, #files)
    end)
  end)

  describe("clear", function()
    it("removes all staged files", function()
      staged.stage("a.lua")
      staged.stage("b.lua")
      staged.clear()
      assert.equals(0, #staged.get_staged())
    end)
  end)
end)
