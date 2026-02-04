-- Tests for Buffer abstraction
-- lua/neosapling/lib/ui/buffer.lua

local Buffer = require("neosapling.lib.ui.buffer")

describe("Buffer", function()
  -- Track buffers created during tests for cleanup
  local test_buffers = {}

  local function create_test_buffer(name)
    local buf = Buffer:new(name)
    table.insert(test_buffers, buf)
    return buf
  end

  after_each(function()
    -- Cleanup all test buffers
    for _, buf in ipairs(test_buffers) do
      if buf:is_valid() then
        buf:destroy()
      end
    end
    test_buffers = {}
  end)

  describe("Buffer:new()", function()
    it("creates new buffer with given name", function()
      local buf = create_test_buffer("neosapling://test-new")
      assert.is_not_nil(buf.handle)
      assert.is_true(buf:is_valid())
      assert.equals("neosapling://test-new", buf.name)
    end)

    it("returns existing buffer if name already exists", function()
      local buf1 = create_test_buffer("neosapling://test-existing")
      local buf2 = create_test_buffer("neosapling://test-existing")
      assert.equals(buf1.handle, buf2.handle)
    end)

    it("buffer has correct buftype (nofile)", function()
      local buf = create_test_buffer("neosapling://test-buftype")
      local buftype = vim.api.nvim_buf_get_option(buf.handle, "buftype")
      assert.equals("nofile", buftype)
    end)

    it("buffer is scratch (unlisted)", function()
      local buf = create_test_buffer("neosapling://test-scratch")
      local listed = vim.api.nvim_buf_get_option(buf.handle, "buflisted")
      assert.is_false(listed)
    end)

    it("buffer namespace is unique per buffer name", function()
      local buf1 = create_test_buffer("neosapling://test-ns1")
      local buf2 = create_test_buffer("neosapling://test-ns2")
      assert.is_not.equals(buf1.namespace, buf2.namespace)
    end)

    it("buffer has swapfile disabled", function()
      local buf = create_test_buffer("neosapling://test-swap")
      local swapfile = vim.api.nvim_buf_get_option(buf.handle, "swapfile")
      assert.is_false(swapfile)
    end)

    it("buffer is not modifiable by default", function()
      local buf = create_test_buffer("neosapling://test-mod")
      local modifiable = vim.api.nvim_buf_get_option(buf.handle, "modifiable")
      assert.is_false(modifiable)
    end)
  end)

  describe("Buffer:set_lines()", function()
    it("sets lines atomically", function()
      local buf = create_test_buffer("neosapling://test-lines")
      local lines = { "line1", "line2", "line3" }
      buf:set_lines(lines)

      local result = buf:get_lines()
      assert.same(lines, result)
    end)

    it("empty lines array clears buffer", function()
      local buf = create_test_buffer("neosapling://test-clear")
      buf:set_lines({ "some", "content" })
      buf:set_lines({})

      local result = buf:get_lines()
      assert.same({ "" }, result)
    end)

    it("buffer is not modifiable after set_lines", function()
      local buf = create_test_buffer("neosapling://test-mod-after")
      buf:set_lines({ "test" })
      local modifiable = vim.api.nvim_buf_get_option(buf.handle, "modifiable")
      assert.is_false(modifiable)
    end)

    it("replaces all existing content", function()
      local buf = create_test_buffer("neosapling://test-replace")
      buf:set_lines({ "old1", "old2", "old3" })
      buf:set_lines({ "new" })

      local result = buf:get_lines()
      assert.same({ "new" }, result)
    end)
  end)

  describe("Buffer:add_highlight()", function()
    it("adds highlight to specified range", function()
      local buf = create_test_buffer("neosapling://test-hl")
      buf:set_lines({ "hello world" })

      -- Add highlight to "hello" (cols 0-5)
      buf:add_highlight(0, 0, 5, "Error")

      -- Verify extmark exists
      local marks = vim.api.nvim_buf_get_extmarks(buf.handle, buf.namespace, 0, -1, { details = true })
      assert.equals(1, #marks)
      assert.equals(0, marks[1][2]) -- line
      assert.equals(0, marks[1][3]) -- col_start
      assert.equals("Error", marks[1][4].hl_group)
    end)

    it("multiple highlights on same line work", function()
      local buf = create_test_buffer("neosapling://test-multi-hl")
      buf:set_lines({ "hello world" })

      buf:add_highlight(0, 0, 5, "Error")
      buf:add_highlight(0, 6, 11, "WarningMsg")

      local marks = vim.api.nvim_buf_get_extmarks(buf.handle, buf.namespace, 0, -1, { details = true })
      assert.equals(2, #marks)
    end)
  end)

  describe("Buffer:clear_highlights()", function()
    it("clears all highlights from namespace", function()
      local buf = create_test_buffer("neosapling://test-clear-hl")
      buf:set_lines({ "test content" })
      buf:add_highlight(0, 0, 4, "Error")
      buf:add_highlight(0, 5, 12, "WarningMsg")

      -- Verify highlights exist
      local before = vim.api.nvim_buf_get_extmarks(buf.handle, buf.namespace, 0, -1, {})
      assert.equals(2, #before)

      buf:clear_highlights()

      local after = vim.api.nvim_buf_get_extmarks(buf.handle, buf.namespace, 0, -1, {})
      assert.equals(0, #after)
    end)

    it("does not affect highlights in other namespaces", function()
      local buf = create_test_buffer("neosapling://test-other-ns")
      buf:set_lines({ "test content" })

      -- Add highlight in buffer's namespace
      buf:add_highlight(0, 0, 4, "Error")

      -- Add highlight in a different namespace
      local other_ns = vim.api.nvim_create_namespace("other_namespace")
      vim.api.nvim_buf_set_extmark(buf.handle, other_ns, 0, 5, {
        end_col = 12,
        hl_group = "WarningMsg",
      })

      -- Clear buffer's namespace
      buf:clear_highlights()

      -- Buffer's namespace should be empty
      local buf_marks = vim.api.nvim_buf_get_extmarks(buf.handle, buf.namespace, 0, -1, {})
      assert.equals(0, #buf_marks)

      -- Other namespace should still have its mark
      local other_marks = vim.api.nvim_buf_get_extmarks(buf.handle, other_ns, 0, -1, {})
      assert.equals(1, #other_marks)
    end)
  end)

  describe("Buffer:destroy()", function()
    it("buffer is invalid after destroy", function()
      local buf = Buffer:new("neosapling://test-destroy")
      assert.is_true(buf:is_valid())

      buf:destroy()

      assert.is_false(buf:is_valid())
    end)

    it("destroy on already-destroyed buffer does not error", function()
      local buf = Buffer:new("neosapling://test-double-destroy")
      buf:destroy()

      -- Should not throw
      assert.has_no.errors(function()
        buf:destroy()
      end)
    end)

    it("buffer handle is no longer valid after destroy", function()
      local buf = Buffer:new("neosapling://test-handle-invalid")
      local handle = buf.handle

      buf:destroy()

      assert.is_false(vim.api.nvim_buf_is_valid(handle))
    end)
  end)

  describe("Buffer:show()", function()
    it("opens buffer in current window with 'current' kind", function()
      local buf = create_test_buffer("neosapling://test-show-current")
      buf:set_lines({ "test content" })

      local original_buf = vim.api.nvim_get_current_buf()
      buf:show("current")

      assert.equals(buf.handle, vim.api.nvim_get_current_buf())

      -- Restore original buffer
      vim.api.nvim_set_current_buf(original_buf)
    end)
  end)

  describe("Buffer:line_count()", function()
    it("returns correct line count", function()
      local buf = create_test_buffer("neosapling://test-linecount")
      buf:set_lines({ "line1", "line2", "line3" })

      assert.equals(3, buf:line_count())
    end)

    it("returns 1 for empty buffer", function()
      local buf = create_test_buffer("neosapling://test-empty-linecount")
      buf:set_lines({})

      assert.equals(1, buf:line_count())
    end)
  end)

  describe("Buffer:get_lines()", function()
    it("returns all lines by default", function()
      local buf = create_test_buffer("neosapling://test-getlines")
      local lines = { "a", "b", "c", "d" }
      buf:set_lines(lines)

      assert.same(lines, buf:get_lines())
    end)

    it("returns slice of lines with start and end", function()
      local buf = create_test_buffer("neosapling://test-getlines-slice")
      buf:set_lines({ "a", "b", "c", "d" })

      local result = buf:get_lines(1, 3) -- lines at index 1 and 2
      assert.same({ "b", "c" }, result)
    end)
  end)
end)
