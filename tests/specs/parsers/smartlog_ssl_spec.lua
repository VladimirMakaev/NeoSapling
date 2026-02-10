-- Tests for SSL smartlog parser (lua/neosapling/lib/parsers/smartlog_ssl.lua)
-- Validates classification of ssl output lines, commit metadata parsing,
-- build() highlight/line_map generation, and byte offset correctness.

local ssl = require("neosapling.lib.parsers.smartlog_ssl")

describe("smartlog_ssl parser", function()
  describe("constants", function()
    it("SSL_TEMPLATE is {ssl}", function()
      assert.equals("{ssl}", ssl.SSL_TEMPLATE)
    end)
  end)

  describe("classify_line()", function()
    it("returns graph_only for nil input", function()
      local result = ssl.classify_line(nil, nil)
      assert.equals("graph_only", result.type)
      assert.equals("", result.raw)
    end)

    it("returns graph_only for empty string", function()
      local result = ssl.classify_line("", nil)
      assert.equals("graph_only", result.type)
      assert.equals("", result.raw)
    end)

    it("classifies Unicode graph-only line", function()
      -- ╷ │ (just graph characters)
      local line = "\xe2\x95\xb7 \xe2\x94\x82"
      local result = ssl.classify_line(line, nil)
      assert.equals("graph_only", result.type)
      assert.equals(line, result.raw)
    end)

    it("classifies ASCII graph-only line", function()
      local line = "  |  "
      local result = ssl.classify_line(line, nil)
      assert.equals("graph_only", result.type)
    end)

    it("classifies simple graph continuation", function()
      -- ╷ (single Unicode graph char)
      local line = "\xe2\x95\xb7"
      local result = ssl.classify_line(line, nil)
      assert.equals("graph_only", result.type)
    end)

    it("classifies draft commit header", function()
      local line = "\xe2\x95\xb7 o  cb07193905  79 minutes ago  vmakaev  D92670841 Accepted \xe2\x9c\x97 (local changes)"
      local result = ssl.classify_line(line, nil)
      assert.equals("commit_header", result.type)
      assert.is_not_nil(result.commit)
      assert.equals("cb07193905", result.commit.node)
      assert.equals("o", result.commit.graphnode)
      assert.equals("79 minutes ago", result.commit.date)
      assert.equals("vmakaev", result.commit.author)
      assert.equals("D92670841", result.commit.phabdiff)
      assert.equals("Accepted", result.commit.phabstatus)
      assert.is_true(result.commit.local_changes)
    end)

    it("classifies public commit with bookmark", function()
      local line = "o  2c60d6d4ac  Today at 03:55  remote/master"
      local result = ssl.classify_line(line, nil)
      assert.equals("commit_header", result.type)
      assert.is_true(result.commit.is_public)
      assert.equals("2c60d6d4ac", result.commit.node)
      assert.equals("Today at 03:55", result.commit.date)
      assert.same({ "remote/master" }, result.commit.remote_bookmarks)
    end)

    it("classifies public anchor commit (no bookmarks)", function()
      local line = "o  bc482c72e3  Yesterday at 14:01"
      local result = ssl.classify_line(line, nil)
      assert.equals("commit_header", result.type)
      assert.is_true(result.commit.is_public)
      assert.equals("bc482c72e3", result.commit.node)
      assert.equals("Yesterday at 14:01", result.commit.date)
      assert.same({}, result.commit.remote_bookmarks)
    end)

    it("classifies commit message line", function()
      local dummy_commit = { node = "cb07193905", graphnode = "o" }
      local line = "\xe2\x95\xb7 \xe2\x94\x82  [lint/linttool] Add --take-rule CLI flag"
      local result = ssl.classify_line(line, dummy_commit)
      assert.equals("commit_message", result.type)
      assert.equals(dummy_commit, result.commit)
    end)

    it("classifies working copy with @ graphnode", function()
      local line = "@  abc1234567  5 minutes ago  user"
      local result = ssl.classify_line(line, nil)
      assert.equals("commit_header", result.type)
      assert.equals("@", result.commit.graphnode)
      assert.equals("abc1234567", result.commit.node)
      assert.equals("user", result.commit.author)
    end)

    it("handles graphnode with * suffix", function()
      local line = "o*  abc1234567  5 min ago  user"
      local result = ssl.classify_line(line, nil)
      assert.equals("commit_header", result.type)
      assert.equals("o*", result.commit.graphnode)
      assert.equals("abc1234567", result.commit.node)
    end)

    it("classifies x (obsolete) graphnode", function()
      local line = "x  deadbeef12  2 days ago  user"
      local result = ssl.classify_line(line, nil)
      assert.equals("commit_header", result.type)
      assert.equals("x", result.commit.graphnode)
      assert.equals("deadbeef12", result.commit.node)
    end)

    it("preserves raw line in all classifications", function()
      local lines = {
        "",
        "\xe2\x95\xb7",
        "o  abc1234567  now  user",
      }
      for _, line in ipairs(lines) do
        local result = ssl.classify_line(line, nil)
        assert.equals(line, result.raw)
      end
    end)

    it("handles graph prefix with multiple Unicode chars before graphnode", function()
      -- ╷ │ o  (multi-column graph)
      local line = "\xe2\x95\xb7 \xe2\x94\x82 o  a1b2c3d4e5  3 hours ago  user"
      local result = ssl.classify_line(line, nil)
      assert.equals("commit_header", result.type)
      assert.equals("a1b2c3d4e5", result.commit.node)
    end)

    it("handles tilde in graph-only lines", function()
      local line = "~"
      local result = ssl.classify_line(line, nil)
      assert.equals("graph_only", result.type)
    end)
  end)

  describe("parse_commit_metadata()", function()
    it("parses draft with all metadata fields", function()
      local commit = ssl.parse_commit_metadata(
        "cb07193905", "o",
        "79 minutes ago  vmakaev  D92670841 Accepted"
      )
      assert.equals("cb07193905", commit.node)
      assert.equals("o", commit.graphnode)
      assert.equals("79 minutes ago", commit.date)
      assert.equals("vmakaev", commit.author)
      assert.equals("D92670841", commit.phabdiff)
      assert.equals("Accepted", commit.phabstatus)
      assert.is_false(commit.is_public)
      assert.is_false(commit.local_changes)
    end)

    it("parses draft without phabricator", function()
      local commit = ssl.parse_commit_metadata("abc1234567", "o", "5 min ago  johndoe")
      assert.equals("5 min ago", commit.date)
      assert.equals("johndoe", commit.author)
      assert.is_nil(commit.phabdiff)
      assert.is_nil(commit.phabstatus)
    end)

    it("parses public with single bookmark", function()
      local commit = ssl.parse_commit_metadata("2c60d6d4ac", "o", "Today at 03:55  remote/master")
      assert.is_true(commit.is_public)
      assert.equals("Today at 03:55", commit.date)
      assert.same({ "remote/master" }, commit.remote_bookmarks)
      assert.is_nil(commit.author)
    end)

    it("parses public with multiple bookmarks", function()
      local commit = ssl.parse_commit_metadata(
        "abc1234567", "o",
        "Today at 03:55  remote/fbcode/stable remote/fbcode/warm"
      )
      assert.is_true(commit.is_public)
      assert.equals("Today at 03:55", commit.date)
      assert.equals(2, #commit.remote_bookmarks)
      assert.equals("remote/fbcode/stable", commit.remote_bookmarks[1])
      assert.equals("remote/fbcode/warm", commit.remote_bookmarks[2])
    end)

    it("parses public anchor (date only)", function()
      local commit = ssl.parse_commit_metadata("bc482c72e3", "o", "Yesterday at 14:01")
      assert.is_true(commit.is_public)
      assert.equals("Yesterday at 14:01", commit.date)
      assert.is_nil(commit.author)
      assert.same({}, commit.remote_bookmarks)
    end)

    it("strips (local changes) and sets flag", function()
      local commit = ssl.parse_commit_metadata(
        "abc1234567", "o",
        "5 min ago  user  D123 Review (local changes)"
      )
      assert.is_true(commit.local_changes)
      assert.equals("user", commit.author)
    end)

    it("extracts signal checkmark", function()
      local commit = ssl.parse_commit_metadata(
        "abc1234567", "o",
        "5 min ago  user  D123 Accepted \xe2\x9c\x93"
      )
      assert.is_not_nil(commit.signal)
      -- ✓ = \xe2\x9c\x93
      assert.equals("\xe2\x9c\x93", commit.signal)
    end)

    it("extracts signal cross", function()
      local commit = ssl.parse_commit_metadata(
        "abc1234567", "o",
        "5 min ago  user  D123 Accepted \xe2\x9c\x97"
      )
      assert.is_not_nil(commit.signal)
      -- ✗ = \xe2\x9c\x97
      assert.equals("\xe2\x9c\x97", commit.signal)
    end)

    it("handles signal + local_changes together", function()
      local commit = ssl.parse_commit_metadata(
        "abc1234567", "o",
        "5 min ago  user  D123 Accepted \xe2\x9c\x97 (local changes)"
      )
      assert.is_true(commit.local_changes)
      assert.is_not_nil(commit.signal)
      assert.equals("\xe2\x9c\x97", commit.signal)
      assert.equals("D123", commit.phabdiff)
      assert.equals("Accepted", commit.phabstatus)
    end)

    it("parses Needs Review status", function()
      local commit = ssl.parse_commit_metadata(
        "abc1234567", "o",
        "2 hours ago  user  D456 Needs Review"
      )
      assert.equals("D456", commit.phabdiff)
      assert.equals("Needs Review", commit.phabstatus)
    end)

    it("parses phabdiff with no status", function()
      -- Edge case: diff ID without status text
      local commit = ssl.parse_commit_metadata(
        "abc1234567", "o",
        "2 hours ago  user  D789"
      )
      assert.equals("D789", commit.phabdiff)
      assert.is_nil(commit.phabstatus)
    end)
  end)

  describe("build()", function()
    it("returns empty results for nil input", function()
      local lines, highlights, line_map = ssl.build(nil)
      assert.same({}, lines)
      assert.same({}, highlights)
      assert.same({}, line_map)
    end)

    it("returns empty results for empty input", function()
      local lines, highlights, line_map = ssl.build({})
      assert.same({}, lines)
      assert.same({}, highlights)
      assert.same({}, line_map)
    end)

    it("processes multi-line ssl output with mixed types", function()
      local input = {
        "\xe2\x95\xb7 o  cb07193905  79 minutes ago  vmakaev  D92670841 Accepted",
        "\xe2\x95\xb7 \xe2\x94\x82  Some commit message here",
        "\xe2\x95\xb7",
        "o  2c60d6d4ac  Today at 03:55  remote/master",
      }
      local lines, highlights, line_map = ssl.build(input)

      -- Lines returned unmodified
      assert.same(input, lines)

      -- Line map populated correctly
      assert.is_not_nil(line_map[1])
      assert.equals("commit", line_map[1].type)
      assert.equals("cb07193905", line_map[1].commit.node)

      assert.is_not_nil(line_map[2])
      assert.equals("message", line_map[2].type)
      assert.equals(line_map[1].commit, line_map[2].commit) -- same reference

      -- Graph-only line 3 has no entry
      assert.is_nil(line_map[3])

      -- Public commit on line 4
      assert.is_not_nil(line_map[4])
      assert.equals("commit", line_map[4].type)
      assert.is_true(line_map[4].commit.is_public)

      -- Highlights should be non-empty
      assert.is_true(#highlights > 0)
    end)

    it("sets commit desc from message line", function()
      local input = {
        "o  abc1234567  5 min ago  user",
        "\xe2\x94\x82  My commit message",
      }
      local _, _, line_map = ssl.build(input)

      assert.equals("My commit message", line_map[1].commit.desc)
    end)

    it("graph-only lines have no line_map entry", function()
      local input = {
        "\xe2\x95\xb7",
        "\xe2\x94\x82",
        "  |  ",
      }
      local _, _, line_map = ssl.build(input)

      assert.is_nil(line_map[1])
      assert.is_nil(line_map[2])
      assert.is_nil(line_map[3])
    end)

    it("generates highlights for commit header fields", function()
      local input = {
        "o  abc1234567  Today at 10:00  user  D123 Accepted",
      }
      local _, highlights, _ = ssl.build(input)

      -- Should have highlights for: hash, date, author, phabdiff, phabstatus
      assert.is_true(#highlights >= 5, "Expected at least 5 highlights, got " .. #highlights)

      -- Check hash highlight
      local hash_hl = nil
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingHash" then
          hash_hl = h
          break
        end
      end
      assert.is_not_nil(hash_hl)
      assert.equals(0, hash_hl.line) -- 0-indexed
    end)

    it("uses NeoSaplingCurrent for @ graphnode", function()
      local input = {
        "@  abc1234567  5 min ago  user",
      }
      local _, highlights, _ = ssl.build(input)

      local current_hl = nil
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingCurrent" then
          current_hl = h
          break
        end
      end
      assert.is_not_nil(current_hl, "Expected NeoSaplingCurrent highlight for @ graphnode")
    end)

    it("generates NeoSaplingBranch highlight for remote bookmarks", function()
      local input = {
        "o  abc1234567  Today at 10:00  remote/master",
      }
      local _, highlights, _ = ssl.build(input)

      local branch_hl = nil
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingBranch" then
          branch_hl = h
          break
        end
      end
      assert.is_not_nil(branch_hl, "Expected NeoSaplingBranch highlight for remote bookmark")
    end)

    it("generates NeoSaplingDesc highlight for commit messages", function()
      local input = {
        "o  abc1234567  5 min ago  user",
        "\xe2\x94\x82  Fix the parsing bug",
      }
      local _, highlights, _ = ssl.build(input)

      local desc_hl = nil
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingDesc" then
          desc_hl = h
          break
        end
      end
      assert.is_not_nil(desc_hl, "Expected NeoSaplingDesc highlight for commit message")
    end)
  end)

  describe("byte offset correctness", function()
    it("hash highlight col_start matches string.find byte position - 1", function()
      -- Line with Unicode graph prefix: ╷ (3 bytes) + space + o + spaces + hash
      local line = "\xe2\x95\xb7 o  abc1234567  5 min ago  user"
      local input = { line }
      local _, highlights, _ = ssl.build(input)

      -- Find hash highlight
      local hash_hl = nil
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingHash" then
          hash_hl = h
          break
        end
      end
      assert.is_not_nil(hash_hl)

      -- Verify against string.find
      local start_byte, end_byte = line:find("abc1234567", 1, true)
      assert.equals(start_byte - 1, hash_hl.col_start)
      assert.equals(end_byte, hash_hl.col_end)
    end)

    it("works correctly for ASCII-only lines", function()
      local line = "o  abc1234567  Yesterday at 10:00  user"
      local input = { line }
      local _, highlights, _ = ssl.build(input)

      -- Find hash highlight
      local hash_hl = nil
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingHash" then
          hash_hl = h
          break
        end
      end
      assert.is_not_nil(hash_hl)

      local start_byte, end_byte = line:find("abc1234567", 1, true)
      assert.equals(start_byte - 1, hash_hl.col_start)
      assert.equals(end_byte, hash_hl.col_end)
    end)

    it("date highlight byte offsets are correct with Unicode prefix", function()
      local line = "\xe2\x95\xb7 o  abc1234567  5 min ago  user"
      local input = { line }
      local _, highlights, _ = ssl.build(input)

      local date_hl = nil
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingDate" then
          date_hl = h
          break
        end
      end
      assert.is_not_nil(date_hl)

      local start_byte, end_byte = line:find("5 min ago", 1, true)
      assert.equals(start_byte - 1, date_hl.col_start)
      assert.equals(end_byte, date_hl.col_end)
    end)

    it("signal highlight byte offsets account for multi-byte signal chars", function()
      -- ✓ is 3 bytes (\xe2\x9c\x93)
      local line = "o  abc1234567  5 min ago  user  D123 Accepted \xe2\x9c\x93"
      local input = { line }
      local _, highlights, _ = ssl.build(input)

      local sig_hl = nil
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingSignalPass" then
          sig_hl = h
          break
        end
      end
      assert.is_not_nil(sig_hl, "Expected NeoSaplingSignalPass highlight")

      local start_byte, end_byte = line:find("\xe2\x9c\x93", 1, true)
      assert.equals(start_byte - 1, sig_hl.col_start)
      assert.equals(end_byte, sig_hl.col_end)
    end)

    it("local_changes highlight byte offsets are correct", function()
      local line = "o  abc1234567  5 min ago  user  D123 Accepted (local changes)"
      local input = { line }
      local _, highlights, _ = ssl.build(input)

      local lc_hl = nil
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingLocalChanges" then
          lc_hl = h
          break
        end
      end
      assert.is_not_nil(lc_hl, "Expected NeoSaplingLocalChanges highlight")

      local start_byte, end_byte = line:find("(local changes)", 1, true)
      assert.equals(start_byte - 1, lc_hl.col_start)
      assert.equals(end_byte, lc_hl.col_end)
    end)

    it("highlights use 0-indexed line numbers", function()
      local input = {
        "\xe2\x95\xb7",  -- graph-only, no highlights
        "o  abc1234567  5 min ago  user",  -- commit header on line index 1
      }
      local _, highlights, _ = ssl.build(input)

      -- All highlights should be on line 1 (0-indexed)
      for _, h in ipairs(highlights) do
        assert.equals(1, h.line, "Expected 0-indexed line 1 for highlight " .. h.hl)
      end
    end)
  end)

  describe("edge cases", function()
    it("handles multiple commits in sequence", function()
      local input = {
        "o  aaa1111111  1 min ago  user1  D111 Accepted",
        "\xe2\x94\x82  First commit message",
        "\xe2\x95\xb7",
        "o  bbb2222222  2 min ago  user2  D222 Needs Review",
        "\xe2\x94\x82  Second commit message",
        "\xe2\x95\xb7",
        "o  ccc3333333  Today at 12:00  remote/master",
      }
      local _, _, line_map = ssl.build(input)

      -- First commit
      assert.equals("aaa1111111", line_map[1].commit.node)
      assert.equals("First commit message", line_map[1].commit.desc)

      -- Message associated with first commit
      assert.equals(line_map[1].commit, line_map[2].commit)

      -- Second commit
      assert.equals("bbb2222222", line_map[4].commit.node)
      assert.equals("Second commit message", line_map[4].commit.desc)

      -- Public commit
      assert.is_true(line_map[7].commit.is_public)
    end)

    it("handles commit with no message line", function()
      -- Public commits don't have message lines
      local input = {
        "o  abc1234567  Today at 10:00  remote/master",
        "\xe2\x95\xb7",
        "o  def7890123  Yesterday  remote/stable",
      }
      local _, _, line_map = ssl.build(input)

      assert.equals("commit", line_map[1].type)
      assert.is_nil(line_map[2])
      assert.equals("commit", line_map[3].type)
    end)

    it("handles @ working copy in the middle of stack", function()
      local input = {
        "o  aaa1111111  1 min ago  user1",
        "\xe2\x94\x82  Top of stack",
        "\xe2\x95\xb7",
        "@  bbb2222222  5 min ago  user1",
        "\xe2\x94\x82  Working copy",
        "\xe2\x95\xb7",
        "o  ccc3333333  Today at 12:00  remote/master",
      }
      local _, highlights, line_map = ssl.build(input)

      -- Working copy should use NeoSaplingCurrent
      assert.equals("@", line_map[4].commit.graphnode)

      local current_hl = nil
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingCurrent" and h.line == 3 then -- 0-indexed line 3
          current_hl = h
          break
        end
      end
      assert.is_not_nil(current_hl, "Expected NeoSaplingCurrent on @ commit line")
    end)

    it("handles signal fail highlight correctly", function()
      -- ✗ = \xe2\x9c\x97
      local line = "o  abc1234567  5 min ago  user  D123 Accepted \xe2\x9c\x97"
      local input = { line }
      local _, highlights, _ = ssl.build(input)

      local fail_hl = nil
      for _, h in ipairs(highlights) do
        if h.hl == "NeoSaplingSignalFail" then
          fail_hl = h
          break
        end
      end
      assert.is_not_nil(fail_hl, "Expected NeoSaplingSignalFail for ✗")
    end)
  end)
end)
