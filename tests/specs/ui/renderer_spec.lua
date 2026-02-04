--- Tests for renderer module.
--- @module tests.specs.ui.renderer_spec

local renderer = require("neosapling.lib.ui.renderer")
local component = require("neosapling.lib.ui.component")

describe("renderer", function()
  describe("text rendering", function()
    it("single text node produces one line", function()
      local tree = component.text("Hello")
      local result = renderer.render(tree)
      assert.equal(1, #result.lines)
    end)

    it("text content is preserved exactly", function()
      local tree = component.text("Hello World!")
      local result = renderer.render(tree)
      assert.equal("Hello World!", result.lines[1])
    end)

    it("text with highlight records highlight instruction", function()
      local tree = component.text("Test", { hl = "Comment" })
      local result = renderer.render(tree)
      assert.equal(1, #result.highlights)
      assert.equal("Comment", result.highlights[1].hl)
    end)

    it("highlight has correct line (0-indexed)", function()
      local tree = component.text("Test", { hl = "Comment" })
      local result = renderer.render(tree)
      assert.equal(0, result.highlights[1].line)
    end)

    it("highlight has correct col_start and col_end", function()
      local tree = component.text("Test", { hl = "Comment" })
      local result = renderer.render(tree)
      assert.equal(0, result.highlights[1].col_start)
      assert.equal(4, result.highlights[1].col_end)
    end)

    it("text without highlight does not record highlight", function()
      local tree = component.text("No highlight")
      local result = renderer.render(tree)
      assert.equal(0, #result.highlights)
    end)

    it("empty text does not record highlight even with hl option", function()
      local tree = component.text("", { hl = "Comment" })
      local result = renderer.render(tree)
      assert.equal(0, #result.highlights)
    end)

    it("handles empty string content", function()
      local tree = component.text("")
      local result = renderer.render(tree)
      assert.equal(1, #result.lines)
      assert.equal("", result.lines[1])
    end)
  end)

  describe("row rendering", function()
    it("row with multiple children produces single line", function()
      local tree = component.row({
        component.text("Hello"),
        component.text(" "),
        component.text("World"),
      })
      local result = renderer.render(tree)
      assert.equal(1, #result.lines)
    end)

    it("children are concatenated on same line", function()
      local tree = component.row({
        component.text("A"),
        component.text("B"),
        component.text("C"),
      })
      local result = renderer.render(tree)
      assert.equal("ABC", result.lines[1])
    end)

    it("empty row produces empty line", function()
      local tree = component.row({})
      local result = renderer.render(tree)
      assert.equal(1, #result.lines)
      assert.equal("", result.lines[1])
    end)

    it("nested highlights track correct column offsets", function()
      local tree = component.row({
        component.text("Pre", { hl = "Type" }),
        component.text("Mid", { hl = "Comment" }),
        component.text("Post", { hl = "String" }),
      })
      local result = renderer.render(tree)

      assert.equal(3, #result.highlights)

      -- First highlight: 0-3
      assert.equal(0, result.highlights[1].col_start)
      assert.equal(3, result.highlights[1].col_end)
      assert.equal("Type", result.highlights[1].hl)

      -- Second highlight: 3-6
      assert.equal(3, result.highlights[2].col_start)
      assert.equal(6, result.highlights[2].col_end)
      assert.equal("Comment", result.highlights[2].hl)

      -- Third highlight: 6-10
      assert.equal(6, result.highlights[3].col_start)
      assert.equal(10, result.highlights[3].col_end)
      assert.equal("String", result.highlights[3].hl)
    end)

    it("multiple highlights on same line work", function()
      local tree = component.row({
        component.text("first", { hl = "A" }),
        component.text("second", { hl = "B" }),
      })
      local result = renderer.render(tree)

      assert.equal(2, #result.highlights)
      assert.equal(0, result.highlights[1].line)
      assert.equal(0, result.highlights[2].line)
    end)
  end)

  describe("col rendering", function()
    it("col with multiple children produces multiple lines", function()
      local tree = component.col({
        component.text("Line 1"),
        component.text("Line 2"),
        component.text("Line 3"),
      })
      local result = renderer.render(tree)
      assert.equal(3, #result.lines)
    end)

    it("one line per child", function()
      local tree = component.col({
        component.text("A"),
        component.text("B"),
      })
      local result = renderer.render(tree)
      assert.equal("A", result.lines[1])
      assert.equal("B", result.lines[2])
    end)

    it("order is preserved", function()
      local tree = component.col({
        component.text("First"),
        component.text("Second"),
        component.text("Third"),
      })
      local result = renderer.render(tree)
      assert.equal("First", result.lines[1])
      assert.equal("Second", result.lines[2])
      assert.equal("Third", result.lines[3])
    end)

    it("empty col produces single empty line", function()
      local tree = component.col({})
      local result = renderer.render(tree)
      assert.equal(1, #result.lines)
      assert.equal("", result.lines[1])
    end)

    it("highlights on different lines have correct line numbers", function()
      local tree = component.col({
        component.text("First", { hl = "A" }),
        component.text("Second", { hl = "B" }),
      })
      local result = renderer.render(tree)

      assert.equal(2, #result.highlights)
      assert.equal(0, result.highlights[1].line) -- 0-indexed
      assert.equal(1, result.highlights[2].line) -- 0-indexed
    end)

    it("column resets to 0 for each new line", function()
      local tree = component.col({
        component.text("ABC", { hl = "A" }),
        component.text("DE", { hl = "B" }),
      })
      local result = renderer.render(tree)

      -- First line highlight
      assert.equal(0, result.highlights[1].col_start)
      assert.equal(3, result.highlights[1].col_end)

      -- Second line highlight - column should reset
      assert.equal(0, result.highlights[2].col_start)
      assert.equal(2, result.highlights[2].col_end)
    end)
  end)

  describe("fold rendering", function()
    it("fold produces lines for header and body", function()
      local tree = component.fold(component.text("Header"), {
        component.text("Body line 1"),
        component.text("Body line 2"),
      })
      local result = renderer.render(tree)
      assert.equal(3, #result.lines)
    end)

    it("fold header is first line", function()
      local tree = component.fold(component.text("Header"), {
        component.text("Body"),
      })
      local result = renderer.render(tree)
      assert.equal("Header", result.lines[1])
    end)

    it("fold body follows header", function()
      local tree = component.fold(component.text("Header"), {
        component.text("Body1"),
        component.text("Body2"),
      })
      local result = renderer.render(tree)
      assert.equal("Body1", result.lines[2])
      assert.equal("Body2", result.lines[3])
    end)

    it("fold region is recorded with correct start/stop", function()
      local tree = component.fold(component.text("Header"), {
        component.text("Body1"),
        component.text("Body2"),
      })
      local result = renderer.render(tree)

      assert.equal(1, #result.folds)
      assert.equal(1, result.folds[1].start) -- 1-indexed
      assert.equal(3, result.folds[1].stop)  -- 1-indexed
    end)

    it("fold regions use 1-indexed line numbers for foldexpr", function()
      local tree = component.col({
        component.text("Before"),
        component.fold(component.text("Header"), {
          component.text("Body"),
        }),
      })
      local result = renderer.render(tree)

      assert.equal(1, #result.folds)
      assert.equal(2, result.folds[1].start) -- Line 2 (1-indexed)
      assert.equal(3, result.folds[1].stop)  -- Line 3 (1-indexed)
    end)

    it("fold with single header (no body) does not record fold region", function()
      local tree = component.fold(component.text("Header only"), {})
      local result = renderer.render(tree)

      assert.equal(1, #result.lines)
      assert.equal("Header only", result.lines[1])
      assert.equal(0, #result.folds)
    end)

    it("nested content inside fold renders correctly", function()
      local tree = component.fold(
        component.row({
          component.text("[+] "),
          component.text("Section"),
        }),
        {
          component.row({
            component.text("  "),
            component.text("Item 1"),
          }),
          component.row({
            component.text("  "),
            component.text("Item 2"),
          }),
        }
      )
      local result = renderer.render(tree)

      assert.equal(3, #result.lines)
      assert.equal("[+] Section", result.lines[1])
      assert.equal("  Item 1", result.lines[2])
      assert.equal("  Item 2", result.lines[3])
    end)

    it("multiple folds recorded separately", function()
      local tree = component.col({
        component.fold(component.text("Fold1"), {
          component.text("Body1"),
        }),
        component.fold(component.text("Fold2"), {
          component.text("Body2"),
        }),
      })
      local result = renderer.render(tree)

      assert.equal(2, #result.folds)
    end)

    it("nested folds work", function()
      local tree = component.fold(component.text("Outer"), {
        component.fold(component.text("Inner"), {
          component.text("Deep"),
        }),
      })
      local result = renderer.render(tree)

      assert.equal(3, #result.lines)
      assert.equal("Outer", result.lines[1])
      assert.equal("Inner", result.lines[2])
      assert.equal("Deep", result.lines[3])

      -- Both outer and inner fold should be recorded
      assert.equal(2, #result.folds)
    end)
  end)

  describe("complex nesting", function()
    it("col containing rows", function()
      local tree = component.col({
        component.row({
          component.text("Row1"),
          component.text("Col1"),
        }),
        component.row({
          component.text("Row2"),
          component.text("Col1"),
        }),
      })
      local result = renderer.render(tree)

      assert.equal(2, #result.lines)
      assert.equal("Row1Col1", result.lines[1])
      assert.equal("Row2Col1", result.lines[2])
    end)

    it("row containing col produces multi-line on same start", function()
      -- Note: This is an edge case - col inside row means vertical content
      -- starts where the row currently is and adds new lines
      local tree = component.row({
        component.text("Pre: "),
        component.col({
          component.text("A"),
          component.text("B"),
        }),
      })
      local result = renderer.render(tree)

      -- Row starts with "Pre: ", then col adds "A" on same line, "B" on new line
      assert.equal(2, #result.lines)
      assert.equal("Pre: A", result.lines[1])
      assert.equal("B", result.lines[2])
    end)

    it("highlights in nested components have correct positions", function()
      local tree = component.col({
        component.row({
          component.text("Label: ", { hl = "Label" }),
          component.text("value", { hl = "Value" }),
        }),
      })
      local result = renderer.render(tree)

      assert.equal(2, #result.highlights)
      assert.equal(0, result.highlights[1].col_start)
      assert.equal(7, result.highlights[1].col_end) -- "Label: " is 7 chars
      assert.equal(7, result.highlights[2].col_start)
      assert.equal(12, result.highlights[2].col_end) -- "value" is 5 chars
    end)
  end)

  describe("integration test", function()
    it("builds realistic status view structure", function()
      -- Simulate a simplified status view
      local tree = component.col({
        -- Header
        component.row({
          component.text("NeoSapling Status", { hl = "NeoSaplingHeader" }),
        }),
        component.text(""),  -- Empty line
        -- Section: Unstaged changes
        component.fold(
          component.row({
            component.text("Unstaged changes", { hl = "NeoSaplingSection" }),
            component.text(" (2)"),
          }),
          {
            component.row({
              component.text("  M ", { hl = "NeoSaplingModified" }),
              component.text("file1.lua"),
            }),
            component.row({
              component.text("  ? ", { hl = "NeoSaplingUntracked" }),
              component.text("file2.lua"),
            }),
          }
        ),
        component.text(""),  -- Empty line
        -- Section: Recent commits
        component.fold(
          component.text("Recent commits", { hl = "NeoSaplingSection" }),
          {
            component.row({
              component.text("abc123 ", { hl = "NeoSaplingHash" }),
              component.text("First commit"),
            }),
          }
        ),
      })

      local result = renderer.render(tree)

      -- Verify lines
      assert.equal(8, #result.lines)
      assert.equal("NeoSapling Status", result.lines[1])
      assert.equal("", result.lines[2])
      assert.equal("Unstaged changes (2)", result.lines[3])
      assert.equal("  M file1.lua", result.lines[4])
      assert.equal("  ? file2.lua", result.lines[5])
      assert.equal("", result.lines[6])
      assert.equal("Recent commits", result.lines[7])
      assert.equal("abc123 First commit", result.lines[8])

      -- Verify some highlights exist
      assert.is_true(#result.highlights > 0)

      -- Verify fold regions
      assert.equal(2, #result.folds)
      -- First fold: lines 3-5 (Unstaged changes)
      assert.equal(3, result.folds[1].start)
      assert.equal(5, result.folds[1].stop)
      -- Second fold: lines 7-8 (Recent commits)
      assert.equal(7, result.folds[2].start)
      assert.equal(8, result.folds[2].stop)
    end)
  end)

  describe("edge cases", function()
    it("nil root produces single empty line", function()
      local result = renderer.render(nil)
      assert.equal(1, #result.lines)
      assert.equal("", result.lines[1])
    end)

    it("node without tag is ignored", function()
      local tree = component.col({
        component.text("Valid"),
        {}, -- Invalid node (no tag)
        component.text("Also valid"),
      })
      local result = renderer.render(tree)
      assert.equal(3, #result.lines)
      assert.equal("Valid", result.lines[1])
      assert.equal("", result.lines[2]) -- Empty line where invalid node was
      assert.equal("Also valid", result.lines[3])
    end)

    it("deeply nested structure renders correctly", function()
      local tree = component.col({
        component.fold(
          component.text("Level 1"),
          {
            component.fold(
              component.text("Level 2"),
              {
                component.fold(
                  component.text("Level 3"),
                  {
                    component.text("Deep content"),
                  }
                ),
              }
            ),
          }
        ),
      })
      local result = renderer.render(tree)

      assert.equal(4, #result.lines)
      assert.equal("Level 1", result.lines[1])
      assert.equal("Level 2", result.lines[2])
      assert.equal("Level 3", result.lines[3])
      assert.equal("Deep content", result.lines[4])
      assert.equal(3, #result.folds) -- Three nested folds
    end)
  end)
end)
