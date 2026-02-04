--- Tests for component primitives module.
--- @module tests.specs.ui.component_spec

local component = require("neosapling.lib.ui.component")

describe("component", function()
  describe("text()", function()
    it("creates text node with content", function()
      local node = component.text("Hello")
      assert.equal("Hello", node.content)
    end)

    it("has correct tag", function()
      local node = component.text("test")
      assert.equal("text", node.tag)
    end)

    it("has empty children", function()
      local node = component.text("test")
      assert.is_table(node.children)
      assert.equal(0, #node.children)
    end)

    it("stores highlight option in options.hl", function()
      local node = component.text("test", { hl = "Comment" })
      assert.equal("Comment", node.options.hl)
    end)

    it("has nil highlight when not provided", function()
      local node = component.text("test")
      assert.is_nil(node.options.hl)
    end)

    it("handles empty string content", function()
      local node = component.text("")
      assert.equal("", node.content)
    end)
  end)

  describe("row()", function()
    it("creates row with children array", function()
      local children = {
        component.text("a"),
        component.text("b"),
      }
      local node = component.row(children)
      assert.is_table(node.children)
      assert.equal(2, #node.children)
    end)

    it("has correct tag", function()
      local node = component.row({})
      assert.equal("row", node.tag)
    end)

    it("preserves child order", function()
      local children = {
        component.text("first"),
        component.text("second"),
        component.text("third"),
      }
      local node = component.row(children)
      assert.equal("first", node.children[1].content)
      assert.equal("second", node.children[2].content)
      assert.equal("third", node.children[3].content)
    end)

    it("accepts empty children array", function()
      local node = component.row({})
      assert.is_table(node.children)
      assert.equal(0, #node.children)
    end)

    it("stores highlight option in options.hl", function()
      local node = component.row({}, { hl = "CursorLine" })
      assert.equal("CursorLine", node.options.hl)
    end)

    it("has nil content", function()
      local node = component.row({})
      assert.is_nil(node.content)
    end)
  end)

  describe("col()", function()
    it("creates col with children array", function()
      local children = {
        component.text("line1"),
        component.text("line2"),
      }
      local node = component.col(children)
      assert.is_table(node.children)
      assert.equal(2, #node.children)
    end)

    it("has correct tag", function()
      local node = component.col({})
      assert.equal("col", node.tag)
    end)

    it("preserves child order", function()
      local children = {
        component.text("top"),
        component.text("middle"),
        component.text("bottom"),
      }
      local node = component.col(children)
      assert.equal("top", node.children[1].content)
      assert.equal("middle", node.children[2].content)
      assert.equal("bottom", node.children[3].content)
    end)

    it("accepts empty children array", function()
      local node = component.col({})
      assert.is_table(node.children)
      assert.equal(0, #node.children)
    end)

    it("has nil content", function()
      local node = component.col({})
      assert.is_nil(node.content)
    end)

    it("preserves custom options", function()
      local node = component.col({}, { custom = "value" })
      assert.equal("value", node.options.custom)
    end)
  end)

  describe("fold()", function()
    it("creates fold with header as first child", function()
      local header = component.text("Header")
      local body = { component.text("Body") }
      local node = component.fold(header, body)
      assert.equal("Header", node.children[1].content)
    end)

    it("has correct tag", function()
      local header = component.text("H")
      local node = component.fold(header, {})
      assert.equal("fold", node.tag)
    end)

    it("has body children after header", function()
      local header = component.text("Header")
      local body = {
        component.text("Body1"),
        component.text("Body2"),
      }
      local node = component.fold(header, body)
      assert.equal(3, #node.children)
      assert.equal("Body1", node.children[2].content)
      assert.equal("Body2", node.children[3].content)
    end)

    it("defaults folded to false", function()
      local header = component.text("H")
      local node = component.fold(header, {})
      assert.is_false(node.options.folded)
    end)

    it("preserves custom folded state", function()
      local header = component.text("H")
      local node = component.fold(header, {}, { folded = true })
      assert.is_true(node.options.folded)
    end)

    it("stores id option", function()
      local header = component.text("H")
      local node = component.fold(header, {}, { id = "section-1" })
      assert.equal("section-1", node.options.id)
    end)

    it("has nil content", function()
      local header = component.text("H")
      local node = component.fold(header, {})
      assert.is_nil(node.content)
    end)

    it("handles empty body", function()
      local header = component.text("H")
      local node = component.fold(header, {})
      assert.equal(1, #node.children)
    end)
  end)

  describe("nesting", function()
    it("row containing text nodes", function()
      local node = component.row({
        component.text("a"),
        component.text("b"),
        component.text("c"),
      })
      assert.equal("row", node.tag)
      assert.equal(3, #node.children)
      for _, child in ipairs(node.children) do
        assert.equal("text", child.tag)
      end
    end)

    it("col containing rows", function()
      local node = component.col({
        component.row({ component.text("r1") }),
        component.row({ component.text("r2") }),
      })
      assert.equal("col", node.tag)
      assert.equal(2, #node.children)
      for _, child in ipairs(node.children) do
        assert.equal("row", child.tag)
      end
    end)

    it("fold with row header and col body", function()
      local header = component.row({
        component.text("Icon"),
        component.text("Title"),
      })
      local body = {
        component.col({
          component.text("line1"),
          component.text("line2"),
        }),
      }
      local node = component.fold(header, body)
      assert.equal("fold", node.tag)
      assert.equal("row", node.children[1].tag)
      assert.equal("col", node.children[2].tag)
    end)

    it("deep nesting (col > fold > row > text)", function()
      local node = component.col({
        component.fold(
          component.row({ component.text("Header") }),
          {
            component.row({
              component.text("Content"),
            }),
          }
        ),
      })
      -- col
      assert.equal("col", node.tag)
      -- fold
      local fold = node.children[1]
      assert.equal("fold", fold.tag)
      -- row (header)
      local header_row = fold.children[1]
      assert.equal("row", header_row.tag)
      -- text
      assert.equal("text", header_row.children[1].tag)
      assert.equal("Header", header_row.children[1].content)
      -- row (body)
      local body_row = fold.children[2]
      assert.equal("row", body_row.tag)
      -- text
      assert.equal("Content", body_row.children[1].content)
    end)

    it("multiple levels of rows and cols", function()
      local node = component.col({
        component.row({
          component.col({
            component.text("deep"),
          }),
        }),
      })
      assert.equal("col", node.tag)
      assert.equal("row", node.children[1].tag)
      assert.equal("col", node.children[1].children[1].tag)
      assert.equal("text", node.children[1].children[1].children[1].tag)
      assert.equal("deep", node.children[1].children[1].children[1].content)
    end)
  end)

  describe("pure data", function()
    it("components are plain tables", function()
      local node = component.text("test")
      assert.equal("table", type(node))
    end)

    it("no metatable set on components", function()
      local node = component.text("test")
      assert.is_nil(getmetatable(node))
    end)

    it("children array is plain table", function()
      local node = component.row({ component.text("a") })
      assert.equal("table", type(node.children))
      assert.is_nil(getmetatable(node.children))
    end)
  end)
end)
