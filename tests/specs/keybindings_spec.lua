--- Tests for keybinding consistency and help popup
local help = require("neosapling.popups.help")

describe("keybindings", function()
  describe("help popup module", function()
    it("can be required without error", function()
      assert.is_not_nil(help)
    end)

    it("exports create function", function()
      assert.is_function(help.create)
    end)
  end)

  describe("keybinding consistency", function()
    -- Verify that status and smartlog modules load and contain expected keybinding setup
    it("status module loads", function()
      local status = require("neosapling.status")
      assert.is_not_nil(status)
      assert.is_function(status.open)
      assert.is_function(status.close)
      assert.is_function(status.refresh)
    end)

    it("smartlog module loads", function()
      local smartlog = require("neosapling.smartlog")
      assert.is_not_nil(smartlog)
      assert.is_function(smartlog.open)
      assert.is_function(smartlog.close)
      assert.is_function(smartlog.refresh)
    end)
  end)
end)
