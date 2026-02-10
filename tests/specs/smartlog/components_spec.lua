-- Tests for smartlog components module (lua/neosapling/smartlog/components.lua)
-- Phase 8.1: Tests updated for ssl-based build() API
-- build(ssl_lines) accepts raw ssl output lines and returns (lines, highlights, line_map)

describe("neosapling.smartlog.components", function()
  local components

  before_each(function()
    components = require("neosapling.smartlog.components")
  end)

  describe("build", function()
    it("returns empty results for empty input", function()
      local lines, highlights, line_map = components.build({})
      assert.same({}, lines)
      assert.same({}, highlights)
      assert.same({}, line_map)
    end)

    it("handles nil input gracefully", function()
      local lines, highlights, line_map = components.build(nil)
      assert.same({}, lines)
      assert.same({}, highlights)
      assert.same({}, line_map)
    end)

    it("parses single draft commit (2 lines)", function()
      local ssl_lines = {
        "o  cb07193905  79 minutes ago  vmakaev  D92670841 Accepted",
        "\xe2\x94\x82  Fix the build issue",
      }
      local lines, highlights, line_map = components.build(ssl_lines)

      -- Lines are returned unmodified
      assert.same(ssl_lines, lines)

      -- Line 1 is a commit header
      assert.is_not_nil(line_map[1])
      assert.equals("commit", line_map[1].type)
      assert.is_table(line_map[1].commit)
      assert.equals("cb07193905", line_map[1].commit.node)
      assert.equals("o", line_map[1].commit.graphnode)
      assert.equals("79 minutes ago", line_map[1].commit.date)
      assert.equals("vmakaev", line_map[1].commit.author)
      assert.equals("D92670841", line_map[1].commit.phabdiff)
      assert.equals("Accepted", line_map[1].commit.phabstatus)

      -- Line 2 is a message line referencing the same commit
      assert.is_not_nil(line_map[2])
      assert.equals("message", line_map[2].type)
      assert.equals(line_map[1].commit, line_map[2].commit) -- same reference

      -- Highlights should contain entries for hash, date, author, phabdiff, phabstatus
      assert.is_true(#highlights >= 5, "Expected at least 5 highlights, got " .. #highlights)
    end)

    it("parses public commit with bookmark", function()
      local ssl_lines = {
        "o  2c60d6d4ac  Today at 03:55  remote/master",
      }
      local lines, highlights, line_map = components.build(ssl_lines)

      assert.same(ssl_lines, lines)
      assert.is_not_nil(line_map[1])
      assert.equals("commit", line_map[1].type)
      assert.is_true(line_map[1].commit.is_public)
      assert.same({ "remote/master" }, line_map[1].commit.remote_bookmarks)

      -- Should have NeoSaplingBranch highlight for bookmark
      local has_branch_hl = false
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingBranch" then
          has_branch_hl = true
          break
        end
      end
      assert.is_true(has_branch_hl, "Expected NeoSaplingBranch highlight for remote bookmark")
    end)

    it("parses mixed output with graph-only lines", function()
      local ssl_lines = {
        "o  cb07193905  79 minutes ago  vmakaev",
        "\xe2\x94\x82  Fix the build issue",
        "\xe2\x94\x82",
        "o  def4567890  2 hours ago  vmakaev",
        "\xe2\x94\x82  Previous change",
      }
      local lines, highlights, line_map = components.build(ssl_lines)

      assert.same(ssl_lines, lines)

      -- Line 1: commit, Line 2: message
      assert.is_not_nil(line_map[1])
      assert.equals("commit", line_map[1].type)
      assert.equals("cb07193905", line_map[1].commit.node)

      assert.is_not_nil(line_map[2])
      assert.equals("message", line_map[2].type)

      -- Line 3: graph_only — no line_map entry
      assert.is_nil(line_map[3])

      -- Line 4: commit, Line 5: message
      assert.is_not_nil(line_map[4])
      assert.equals("commit", line_map[4].type)
      assert.equals("def4567890", line_map[4].commit.node)

      assert.is_not_nil(line_map[5])
      assert.equals("message", line_map[5].type)

      assert.is_true(#highlights > 0)
    end)

    it("identifies @ graphnode and uses NeoSaplingCurrent highlight", function()
      local ssl_lines = {
        "@  abc1234567  5 minutes ago  user",
        "\xe2\x94\x82  Working copy commit",
      }
      local lines, highlights, line_map = components.build(ssl_lines)

      assert.same(ssl_lines, lines)
      assert.equals("@", line_map[1].commit.graphnode)

      -- Hash highlight should use NeoSaplingCurrent instead of NeoSaplingHash
      local has_current_hl = false
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingCurrent" then
          has_current_hl = true
          break
        end
      end
      assert.is_true(has_current_hl, "Expected NeoSaplingCurrent highlight for @ graphnode")

      -- Should NOT have NeoSaplingHash for the @ commit
      local has_hash_hl = false
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingHash" and h.line == 0 then
          has_hash_hl = true
          break
        end
      end
      assert.is_false(has_hash_hl, "Should not have NeoSaplingHash for @ commit")
    end)

    it("handles byte offsets correctly with Unicode graph prefix", function()
      -- ╷ (3 bytes) + space + o + spaces + hash
      local ssl_lines = {
        "\xe2\x95\xb7 o  abc1234567  5 min ago  user",
      }
      local lines, highlights, line_map = components.build(ssl_lines)

      assert.same(ssl_lines, lines)
      assert.is_not_nil(line_map[1])
      assert.equals("commit", line_map[1].type)

      -- Verify hash highlight byte offsets
      local hash_hl = nil
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingHash" then
          hash_hl = h
          break
        end
      end
      assert.is_not_nil(hash_hl)

      -- Verify with string.find byte positions
      local start_byte, end_byte = ssl_lines[1]:find("abc1234567", 1, true)
      assert.equals(start_byte - 1, hash_hl.col_start, "col_start should be Lua byte pos - 1 (0-indexed)")
      assert.equals(end_byte, hash_hl.col_end, "col_end should be Lua byte pos (exclusive)")
    end)

    it("sets commit desc from message line", function()
      local ssl_lines = {
        "o  abc1234567  5 min ago  user",
        "\xe2\x94\x82  My commit message",
      }
      local _, _, line_map = components.build(ssl_lines)

      assert.equals("My commit message", line_map[1].commit.desc)
    end)

    it("message line references same commit object as header", function()
      local ssl_lines = {
        "o  abc1234567  5 min ago  user",
        "\xe2\x94\x82  Some message",
      }
      local _, _, line_map = components.build(ssl_lines)

      -- Both entries should reference the same commit table
      assert.equals(line_map[1].commit, line_map[2].commit)
    end)

    it("generates NeoSaplingDesc highlight for message lines", function()
      local ssl_lines = {
        "o  abc1234567  5 min ago  user",
        "\xe2\x94\x82  Fix the parsing bug",
      }
      local _, highlights, _ = components.build(ssl_lines)

      local has_desc_hl = false
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingDesc" and h.line == 1 then
          has_desc_hl = true
          break
        end
      end
      assert.is_true(has_desc_hl, "Expected NeoSaplingDesc highlight on message line")
    end)
  end)
end)
