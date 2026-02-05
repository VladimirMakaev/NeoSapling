--- Tests for popup display functionality.
--- @module tests.specs.popups.init_spec

describe("neosapling.popups", function()
  local popups
  local builder

  before_each(function()
    package.loaded["neosapling.popups"] = nil
    package.loaded["neosapling.popups.builder"] = nil
    popups = require("neosapling.popups")
    builder = require("neosapling.popups.builder")
  end)

  after_each(function()
    pcall(popups.close)
  end)

  describe("show()", function()
    it("creates popup buffer", function()
      local def = builder.builder()
        :name("Test")
        :group()
        :action("t", "Test", function() end)
        :build()
      local buf = popups.show(def)
      assert.is_not_nil(buf)
      assert.is_true(buf:is_valid())
    end)

    it("buffer has content from popup definition", function()
      local def = builder.builder()
        :name("MyPopup")
        :group("Actions")
        :action("a", "Do Action", function() end)
        :build()
      local buf = popups.show(def)
      local lines = buf:get_lines()
      -- Should contain popup name and action description
      local content = table.concat(lines, "\n")
      assert.is_true(content:find("MyPopup") ~= nil)
      assert.is_true(content:find("Do Action") ~= nil)
    end)

    it("opens floating window", function()
      local def = builder.builder()
        :name("FloatTest")
        :group()
        :action("x", "X", function() end)
        :build()
      popups.show(def)
      -- Current window should be popup's float window
      local win = vim.api.nvim_get_current_win()
      local config = vim.api.nvim_win_get_config(win)
      assert.is_not_nil(config.relative)
      assert.equals("editor", config.relative)
    end)

    it("float window has border", function()
      local def = builder.builder()
        :name("BorderTest")
        :group()
        :action("b", "B", function() end)
        :build()
      popups.show(def)
      local win = vim.api.nvim_get_current_win()
      local config = vim.api.nvim_win_get_config(win)
      -- Border is returned as table of chars when read back from nvim_win_get_config
      assert.is_not_nil(config.border)
      assert.is_table(config.border)
      -- Rounded border starts with top-left corner character
      assert.is_true(#config.border > 0)
    end)

    it("float window has title", function()
      local def = builder.builder()
        :name("TitleTest")
        :group()
        :action("t", "T", function() end)
        :build()
      popups.show(def)
      local win = vim.api.nvim_get_current_win()
      local config = vim.api.nvim_win_get_config(win)
      assert.is_not_nil(config.title)
      local title = type(config.title) == "table" and config.title[1][1] or config.title
      assert.is_true(title:find("TitleTest") ~= nil)
    end)
  end)

  describe("close()", function()
    it("closes active popup", function()
      local def = builder.builder()
        :name("CloseTest")
        :group()
        :action("c", "C", function() end)
        :build()
      local buf = popups.show(def)
      local win = vim.api.nvim_get_current_win()
      popups.close()
      assert.is_false(buf:is_valid())
      assert.is_false(vim.api.nvim_win_is_valid(win))
    end)

    it("does not error when no popup is open", function()
      assert.has_no.errors(function()
        popups.close()
      end)
    end)

    it("does not error on double close", function()
      local def = builder.builder()
        :name("DoubleClose")
        :group()
        :action("d", "D", function() end)
        :build()
      popups.show(def)
      popups.close()
      assert.has_no.errors(function()
        popups.close()
      end)
    end)

    it("buffer is destroyed after close", function()
      local def = builder.builder()
        :name("DestroyTest")
        :group()
        :action("x", "X", function() end)
        :build()
      local buf = popups.show(def)
      local handle = buf.handle
      popups.close()
      assert.is_false(vim.api.nvim_buf_is_valid(handle))
    end)
  end)

  describe("single popup constraint", function()
    it("closes existing popup when showing new one", function()
      local def1 = builder.builder()
        :name("Popup1")
        :group()
        :action("a", "A", function() end)
        :build()
      local def2 = builder.builder()
        :name("Popup2")
        :group()
        :action("b", "B", function() end)
        :build()

      local buf1 = popups.show(def1)
      local buf2 = popups.show(def2)

      assert.is_false(buf1:is_valid())
      assert.is_true(buf2:is_valid())
    end)

    it("only one floating window active at a time", function()
      local def1 = builder.builder()
        :name("Single1")
        :group()
        :action("s", "S", function() end)
        :build()
      local def2 = builder.builder()
        :name("Single2")
        :group()
        :action("s", "S", function() end)
        :build()

      popups.show(def1)
      local win1 = vim.api.nvim_get_current_win()
      popups.show(def2)
      local win2 = vim.api.nvim_get_current_win()

      assert.is_false(vim.api.nvim_win_is_valid(win1))
      assert.is_true(vim.api.nvim_win_is_valid(win2))
    end)
  end)

  describe("keymaps", function()
    it("q is mapped to close", function()
      local def = builder.builder()
        :name("QMap")
        :group()
        :action("x", "X", function() end)
        :build()
      local buf = popups.show(def)
      local keymaps = vim.api.nvim_buf_get_keymap(buf.handle, "n")
      local has_q = false
      for _, km in ipairs(keymaps) do
        if km.lhs == "q" then
          has_q = true
          break
        end
      end
      assert.is_true(has_q)
    end)

    it("Escape is mapped to close", function()
      local def = builder.builder()
        :name("EscMap")
        :group()
        :action("x", "X", function() end)
        :build()
      local buf = popups.show(def)
      local keymaps = vim.api.nvim_buf_get_keymap(buf.handle, "n")
      local has_esc = false
      for _, km in ipairs(keymaps) do
        if km.lhs == "<Esc>" then
          has_esc = true
          break
        end
      end
      assert.is_true(has_esc)
    end)

    it("action keys are mapped to buffer", function()
      local def = builder.builder()
        :name("ActionMap")
        :group()
        :action("a", "Action A", function() end)
        :action("b", "Action B", function() end)
        :build()
      local buf = popups.show(def)
      local keymaps = vim.api.nvim_buf_get_keymap(buf.handle, "n")
      local mapped_keys = {}
      for _, km in ipairs(keymaps) do
        mapped_keys[km.lhs] = true
      end
      assert.is_true(mapped_keys["a"])
      assert.is_true(mapped_keys["b"])
    end)

    it("array keys are all mapped", function()
      local def = builder.builder()
        :name("ArrayKeys")
        :group()
        :action({ "x", "y", "z" }, "Multi-key", function() end)
        :build()
      local buf = popups.show(def)
      local keymaps = vim.api.nvim_buf_get_keymap(buf.handle, "n")
      local mapped_keys = {}
      for _, km in ipairs(keymaps) do
        mapped_keys[km.lhs] = true
      end
      assert.is_true(mapped_keys["x"])
      assert.is_true(mapped_keys["y"])
      assert.is_true(mapped_keys["z"])
    end)
  end)

  describe("_setup_keymaps()", function()
    it("is exposed for testing", function()
      assert.is_function(popups._setup_keymaps)
    end)
  end)
end)
