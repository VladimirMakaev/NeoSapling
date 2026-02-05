--- Tests for config module.
--- @module tests.specs.lib.config_spec

describe("neosapling.lib.config", function()
  local config

  before_each(function()
    package.loaded["neosapling.lib.config"] = nil
    config = require("neosapling.lib.config")
  end)

  describe("defaults", function()
    it("has mappings", function()
      assert.is_table(config.values.mappings)
    end)

    it("has mappings.status", function()
      assert.is_table(config.values.mappings.status)
    end)

    it("has popup config", function()
      assert.is_table(config.values.popup)
    end)

    it("has popup.border", function()
      assert.is_not_nil(config.values.popup.border)
    end)

    it("has signs config", function()
      assert.is_table(config.values.signs)
    end)

    it("has signs.modified", function()
      assert.is_not_nil(config.values.signs.modified)
    end)

    it("has signs.added", function()
      assert.is_not_nil(config.values.signs.added)
    end)

    it("has signs.removed", function()
      assert.is_not_nil(config.values.signs.removed)
    end)

    it("has signs.untracked", function()
      assert.is_not_nil(config.values.signs.untracked)
    end)

    it("mappings.status has help key", function()
      assert.is_not_nil(config.values.mappings.status["?"])
    end)

    it("mappings.status has commit key", function()
      assert.is_not_nil(config.values.mappings.status["c"])
    end)

    it("mappings.status has close key", function()
      assert.is_not_nil(config.values.mappings.status["q"])
    end)

    it("mappings.status has toggle_fold key", function()
      assert.is_not_nil(config.values.mappings.status["<Tab>"])
    end)
  end)

  describe("setup()", function()
    it("merges user options with defaults", function()
      config.setup({ popup = { border = "single" } })
      assert.equals("single", config.values.popup.border)
    end)

    it("preserves unspecified defaults after merge", function()
      config.setup({ popup = { border = "single" } })
      assert.is_table(config.values.mappings)
      assert.is_not_nil(config.values.mappings.status)
    end)

    it("deep merges nested tables", function()
      config.setup({ mappings = { status = { ["x"] = "custom" } } })
      -- New key added
      assert.equals("custom", config.values.mappings.status["x"])
      -- Existing keys preserved
      assert.equals("help", config.values.mappings.status["?"])
    end)

    it("handles nil opts", function()
      config.setup(nil)
      assert.is_table(config.values)
      assert.is_table(config.values.popup)
    end)

    it("handles empty opts", function()
      config.setup({})
      assert.is_table(config.values.popup)
      assert.is_table(config.values.mappings)
    end)

    it("user options override defaults", function()
      config.setup({ signs = { modified = "X" } })
      assert.equals("X", config.values.signs.modified)
    end)

    it("does not mutate defaults on subsequent calls", function()
      config.setup({ popup = { border = "none" } })
      -- Reload module to get fresh defaults
      package.loaded["neosapling.lib.config"] = nil
      local fresh = require("neosapling.lib.config")
      -- Defaults should be intact
      assert.equals("rounded", fresh.values.popup.border)
    end)

    it("can be called multiple times", function()
      config.setup({ popup = { border = "single" } })
      config.setup({ popup = { border = "double" } })
      assert.equals("double", config.values.popup.border)
    end)
  end)

  describe("get()", function()
    before_each(function()
      config.setup({})
    end)

    it("returns value for simple key", function()
      local popup = config.get("popup")
      assert.is_table(popup)
    end)

    it("returns value for dotted path", function()
      local status = config.get("mappings.status")
      assert.is_table(status)
    end)

    it("returns specific value at deep path", function()
      local help = config.get("mappings.status.?")
      assert.equals("help", help)
    end)

    it("returns nil for non-existent key", function()
      local result = config.get("nonexistent")
      assert.is_nil(result)
    end)

    it("returns nil for invalid path", function()
      local result = config.get("popup.nonexistent.deep")
      assert.is_nil(result)
    end)

    it("returns nil for path through non-table", function()
      local result = config.get("popup.border.something")
      assert.is_nil(result)
    end)

    it("works with custom config values", function()
      config.setup({ custom = { nested = { value = 42 } } })
      local result = config.get("custom.nested.value")
      assert.equals(42, result)
    end)

    it("returns string values correctly", function()
      local border = config.get("popup.border")
      assert.equals("rounded", border)
    end)
  end)

  describe("values property", function()
    it("is accessible directly", function()
      assert.is_table(config.values)
    end)

    it("reflects setup changes", function()
      config.setup({ popup = { border = "shadow" } })
      assert.equals("shadow", config.values.popup.border)
    end)

    it("contains all default sections", function()
      assert.is_not_nil(config.values.mappings)
      assert.is_not_nil(config.values.popup)
      assert.is_not_nil(config.values.signs)
    end)
  end)
end)
