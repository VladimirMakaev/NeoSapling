-- Tests for components module (lua/neosapling/status/components.lua)
-- Validates component tree building for status view

local components = require("neosapling.status.components")

describe("components module", function()
  -- Empty status fixture for testing
  local function empty_status()
    return {
      modified = {},
      added = {},
      removed = {},
      unknown = {},
      missing = {},
      ignored = {},
      clean = {},
    }
  end

  describe("build()", function()
    describe("basic structure", function()
      it("returns tree and line_map tuple", function()
        local tree, line_map = components.build({
          status = empty_status(),
          commits = {},
          bookmarks = {},
        })

        assert.is_not_nil(tree)
        assert.is_table(tree)
        assert.is_not_nil(line_map)
        assert.is_table(line_map)
      end)

      it("creates col as root node", function()
        local tree, _ = components.build({
          status = empty_status(),
          commits = {},
          bookmarks = {},
        })

        assert.equals("col", tree.tag)
      end)

      it("creates header for empty status", function()
        local tree, _ = components.build({
          status = empty_status(),
          commits = {},
          bookmarks = {},
        })

        assert.is_not_nil(tree.children)
        assert.is_true(#tree.children >= 1)
        -- First child should be header row
        assert.equals("row", tree.children[1].tag)
      end)

      it("header contains NeoSapling Status text", function()
        local tree, _ = components.build({
          status = empty_status(),
          commits = {},
          bookmarks = {},
        })

        local header = tree.children[1]
        assert.equals("row", header.tag)
        -- Row should contain text child with header content
        local found_header = false
        for _, child in ipairs(header.children) do
          if child.content and child.content:find("NeoSapling Status") then
            found_header = true
            break
          end
        end
        assert.is_true(found_header, "Should have NeoSapling Status header text")
      end)
    end)

    describe("Untracked section", function()
      it("creates Untracked section for unknown files", function()
        local status = empty_status()
        status.unknown = {
          { status = "?", path = "new_file.lua" },
        }

        local tree, _ = components.build({
          status = status,
          commits = {},
          bookmarks = {},
        })

        -- Find fold with untracked content
        local found = false
        for _, child in ipairs(tree.children) do
          if child.tag == "fold" and child.options and child.options.id == "untracked" then
            found = true
          end
        end
        assert.is_true(found, "Should have Untracked files section")
      end)

      it("Untracked section contains file entries", function()
        local status = empty_status()
        status.unknown = {
          { status = "?", path = "file1.lua" },
          { status = "?", path = "file2.lua" },
        }

        local tree, _ = components.build({
          status = status,
          commits = {},
          bookmarks = {},
        })

        local untracked_fold = nil
        for _, child in ipairs(tree.children) do
          if child.tag == "fold" and child.options and child.options.id == "untracked" then
            untracked_fold = child
            break
          end
        end

        assert.is_not_nil(untracked_fold)
        -- Should have header + 2 files = 3 children
        assert.equals(3, #untracked_fold.children)
      end)

      it("populates line_map with file items for untracked", function()
        local status = empty_status()
        status.unknown = {
          { status = "?", path = "file1.lua" },
          { status = "?", path = "file2.lua" },
        }

        local _, line_map = components.build({
          status = status,
          commits = {},
          bookmarks = {},
        })

        local file_count = 0
        for _, item in pairs(line_map) do
          if item.type == "file" then
            file_count = file_count + 1
          end
        end
        assert.equals(2, file_count)
      end)
    end)

    describe("Unstaged section", function()
      it("creates Unstaged section for modified files", function()
        local status = empty_status()
        status.modified = {
          { status = "M", path = "changed.lua" },
        }

        local tree, _ = components.build({
          status = status,
          commits = {},
          bookmarks = {},
        })

        local found = false
        for _, child in ipairs(tree.children) do
          if child.tag == "fold" and child.options and child.options.id == "unstaged" then
            found = true
          end
        end
        assert.is_true(found, "Should have Unstaged changes section")
      end)
    end)

    describe("Staged section", function()
      it("creates Staged section for added files", function()
        local status = empty_status()
        status.added = {
          { status = "A", path = "new.lua" },
        }

        local tree, _ = components.build({
          status = status,
          commits = {},
          bookmarks = {},
        })

        local found = false
        for _, child in ipairs(tree.children) do
          if child.tag == "fold" and child.options and child.options.id == "staged" then
            found = true
          end
        end
        assert.is_true(found, "Should have Staged changes section")
      end)
    end)

    describe("Current Stack section", function()
      it("creates Current Stack section for commits", function()
        local tree, _ = components.build({
          status = empty_status(),
          commits = {
            { node = "abc123", graphnode = "@", author = "user", date = "1h ago", desc = "Test commit", bookmarks = {} },
          },
          bookmarks = {},
        })

        local found = false
        for _, child in ipairs(tree.children) do
          if child.tag == "fold" and child.options and child.options.id == "commits" then
            found = true
          end
        end
        assert.is_true(found, "Should have Current Stack section")
      end)

      it("filters obsolete commits from Current Stack", function()
        local _, line_map = components.build({
          status = empty_status(),
          commits = {
            { node = "abc123", graphnode = "@", author = "user", date = "1h ago", desc = "Current", bookmarks = {} },
            { node = "def456", graphnode = "x", author = "user", date = "2h ago", desc = "Obsolete", bookmarks = {} },
          },
          bookmarks = {},
        })

        -- Count commits in line_map (non-obsolete should be in commits section)
        local current_stack_commits = 0
        for _, item in pairs(line_map) do
          if item.type == "commit" and item.commit and item.commit.graphnode ~= "x" then
            current_stack_commits = current_stack_commits + 1
          end
        end
        assert.equals(1, current_stack_commits)
      end)

      it("populates line_map with commit items", function()
        local _, line_map = components.build({
          status = empty_status(),
          commits = {
            { node = "abc123", graphnode = "@", author = "user", date = "1h ago", desc = "Test", bookmarks = {} },
          },
          bookmarks = {},
        })

        local found_commit = false
        for _, item in pairs(line_map) do
          if item.type == "commit" then
            found_commit = true
            assert.equals("abc123", item.commit.node)
          end
        end
        assert.is_true(found_commit, "Should have commit in line_map")
      end)
    end)

    describe("Recent Stacks section", function()
      it("creates Recent Stacks section for obsolete commits", function()
        local tree, _ = components.build({
          status = empty_status(),
          commits = {
            { node = "abc123", graphnode = "@", author = "user", date = "1h ago", desc = "Current", bookmarks = {} },
            { node = "def456", graphnode = "x", author = "user", date = "2h ago", desc = "Obsolete", bookmarks = {} },
          },
          bookmarks = {},
        })

        local found = false
        for _, child in ipairs(tree.children) do
          if child.tag == "fold" and child.options and child.options.id == "Recent Stacks" then
            found = true
            -- Should be folded by default
            assert.is_true(child.options.folded, "Recent Stacks should be folded by default")
          end
        end
        assert.is_true(found, "Should have Recent Stacks section")
      end)

      it("does not create Recent Stacks if no obsolete commits", function()
        local tree, _ = components.build({
          status = empty_status(),
          commits = {
            { node = "abc123", graphnode = "@", author = "user", date = "1h ago", desc = "Current", bookmarks = {} },
          },
          bookmarks = {},
        })

        local found = false
        for _, child in ipairs(tree.children) do
          if child.tag == "fold" and child.options and child.options.id == "Recent Stacks" then
            found = true
          end
        end
        assert.is_false(found, "Should not have Recent Stacks section without obsolete commits")
      end)
    end)

    describe("Bookmarks section", function()
      it("creates Bookmarks section for bookmarks", function()
        local tree, _ = components.build({
          status = empty_status(),
          commits = {},
          bookmarks = {
            { name = "main", node = "abc123def456" },
          },
        })

        local found = false
        for _, child in ipairs(tree.children) do
          if child.tag == "fold" and child.options and child.options.id == "Bookmarks" then
            found = true
            -- Should be folded by default
            assert.is_true(child.options.folded, "Bookmarks should be folded by default")
          end
        end
        assert.is_true(found, "Should have Bookmarks section")
      end)

      it("does not create Bookmarks section if empty", function()
        local tree, _ = components.build({
          status = empty_status(),
          commits = {},
          bookmarks = {},
        })

        local found = false
        for _, child in ipairs(tree.children) do
          if child.tag == "fold" and child.options and child.options.id == "Bookmarks" then
            found = true
          end
        end
        assert.is_false(found, "Should not have Bookmarks section when empty")
      end)

      it("populates line_map with bookmark items", function()
        local _, line_map = components.build({
          status = empty_status(),
          commits = {},
          bookmarks = {
            { name = "main", node = "abc123" },
            { name = "feature", node = "def456" },
          },
        })

        local bookmark_count = 0
        for _, item in pairs(line_map) do
          if item.type == "bookmark" then
            bookmark_count = bookmark_count + 1
          end
        end
        assert.equals(2, bookmark_count)
      end)
    end)

    describe("line_map population", function()
      it("maps section headers to section items", function()
        local status = empty_status()
        status.unknown = {
          { status = "?", path = "new.lua" },
        }

        local _, line_map = components.build({
          status = status,
          commits = {},
          bookmarks = {},
        })

        local found_section = false
        for _, item in pairs(line_map) do
          if item.type == "section" and item.id == "untracked" then
            found_section = true
          end
        end
        assert.is_true(found_section, "Should have section in line_map")
      end)

      it("file items have section reference", function()
        local status = empty_status()
        status.modified = {
          { status = "M", path = "changed.lua" },
        }

        local _, line_map = components.build({
          status = status,
          commits = {},
          bookmarks = {},
        })

        for _, item in pairs(line_map) do
          if item.type == "file" then
            assert.equals("unstaged", item.section)
          end
        end
      end)

      it("handles complex status with all sections", function()
        local status = empty_status()
        status.unknown = { { status = "?", path = "new.lua" } }
        status.modified = { { status = "M", path = "changed.lua" } }
        status.added = { { status = "A", path = "staged.lua" } }

        local _, line_map = components.build({
          status = status,
          commits = {
            { node = "abc", graphnode = "@", author = "u", date = "1h", desc = "test", bookmarks = {} },
          },
          bookmarks = {
            { name = "main", node = "abc123" },
          },
        })

        -- Count different item types
        local counts = { section = 0, file = 0, commit = 0, bookmark = 0 }
        for _, item in pairs(line_map) do
          if counts[item.type] then
            counts[item.type] = counts[item.type] + 1
          end
        end

        assert.is_true(counts.section >= 4, "Should have at least 4 sections")
        assert.equals(3, counts.file)
        assert.equals(1, counts.commit)
        assert.equals(1, counts.bookmark)
      end)
    end)

    describe("expanded files with diff", function()
      it("includes diff hunks when file is expanded", function()
        local status = empty_status()
        status.modified = {
          { status = "M", path = "changed.lua" },
        }

        local _, line_map = components.build({
          status = status,
          commits = {},
          bookmarks = {},
          expanded_files = {
            ["changed.lua"] = {
              hunks = {
                {
                  old_start = 1,
                  old_count = 3,
                  new_start = 1,
                  new_count = 5,
                  lines = { "+added", "-removed", " context" },
                },
              },
            },
          },
        })

        local hunk_count = 0
        local diff_line_count = 0
        for _, item in pairs(line_map) do
          if item.type == "hunk" then
            hunk_count = hunk_count + 1
          elseif item.type == "diff_line" then
            diff_line_count = diff_line_count + 1
          end
        end

        assert.equals(1, hunk_count)
        assert.equals(3, diff_line_count)
      end)
    end)
  end)
end)
