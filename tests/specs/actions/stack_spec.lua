--- Integration tests for stack action handlers
--- Verifies actual sl state changes using sapling_harness
local stack = require("neosapling.actions.stack")
local harness = require("tests.util.sapling_harness")

describe("stack operations", function()
  local repo_path

  before_each(function()
    if not harness.sl_available() then
      pending("sl not available")
      return
    end
    repo_path = harness.create_repo()

    -- Create a multi-commit stack for navigation tests
    -- harness.create_repo() already creates test.txt with "Initial commit"
    -- Add file1.txt in a new commit
    harness.write_file("file1.txt", "first file content")
    vim.fn.system("cd " .. repo_path .. " && sl add file1.txt")
    vim.fn.system("cd " .. repo_path .. " && sl commit -m 'First commit'")

    -- Add file2.txt in another commit
    harness.write_file("file2.txt", "second file content")
    vim.fn.system("cd " .. repo_path .. " && sl add file2.txt")
    vim.fn.system("cd " .. repo_path .. " && sl commit -m 'Second commit'")
  end)

  after_each(function()
    harness.cleanup()
  end)

  describe("goto_commit", function()
    it("changes current commit", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      -- Get the first commit hash (the "Initial commit" from harness)
      local first_hash = vim.trim(vim.fn.system("cd " .. repo_path .. " && sl log -r 'first(all())' -T '{node|short}'"))
      assert.is_truthy(first_hash ~= "", "should have first commit hash")

      -- Current commit should be "Second commit" (the tip)
      local current_before = vim.trim(vim.fn.system("cd " .. repo_path .. " && sl log -r '.' -T '{node|short}'"))
      assert.is_not.equal(first_hash, current_before, "should start at different commit")

      -- Navigate to first commit
      stack.goto_commit(first_hash)

      -- Wait for goto to complete
      local changed = vim.wait(3000, function()
        local current = vim.trim(vim.fn.system("cd " .. repo_path .. " && sl log -r '.' -T '{node|short}'"))
        return current == first_hash
      end, 200)

      assert.is_true(changed, "current commit should have changed to first commit")
    end)
  end)

  describe("amend_no_edit", function()
    it("amends current commit with staged changes", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      -- Modify file2.txt (which was added in the current "Second commit")
      harness.write_file("file2.txt", "amended content for file2")

      -- Call amend (amend picks up all working copy changes)
      stack.amend_no_edit()

      -- Wait for amend to complete - sl status should show clean working copy
      local amended = vim.wait(3000, function()
        local status = vim.trim(vim.fn.system("cd " .. repo_path .. " && sl status"))
        return status == ""
      end, 200)

      assert.is_true(amended, "amend should absorb changes into current commit (clean status)")
    end)
  end)

  describe("uncommit", function()
    it("removes current commit keeping changes", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      -- Get current commit hash before uncommit
      local current_hash = vim.trim(vim.fn.system("cd " .. repo_path .. " && sl log -r '.' -T '{node|short}'"))

      -- Uncommit should move to parent and put changes back in working copy
      stack.uncommit()

      -- Wait for uncommit to complete - current commit should change
      local uncommitted = vim.wait(3000, function()
        local new_hash = vim.trim(vim.fn.system("cd " .. repo_path .. " && sl log -r '.' -T '{node|short}'"))
        return new_hash ~= current_hash
      end, 200)

      assert.is_true(uncommitted, "current commit should have changed after uncommit")

      -- Verify that the previously committed file shows as added/modified in status
      local status = vim.trim(vim.fn.system("cd " .. repo_path .. " && sl status"))
      assert.is_truthy(status:match("file2"), "file2.txt should appear in status after uncommit")
    end)
  end)

  describe("hide", function()
    it("hides a commit", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      -- Get the second commit hash (current tip)
      local second_hash = vim.trim(vim.fn.system("cd " .. repo_path .. " && sl log -r '.' -T '{node|short}'"))

      -- Navigate to first commit so we're not on the commit we're hiding
      local first_hash = vim.trim(vim.fn.system("cd " .. repo_path .. " && sl log -r 'first(all())' -T '{node|short}'"))

      -- Use synchronous goto to ensure we're at first commit before hiding
      vim.fn.system("cd " .. repo_path .. " && sl goto " .. first_hash)

      -- Hide the second commit
      stack.hide(second_hash)

      -- Wait for hide to complete
      local hidden = vim.wait(3000, function()
        local all_commits = vim.trim(vim.fn.system("cd " .. repo_path .. " && sl log -r 'all()' -T '{node|short}\\n'"))
        return not all_commits:match(second_hash)
      end, 200)

      assert.is_true(hidden, "hidden commit should no longer appear in all()")
    end)
  end)

  describe("absorb", function()
    it("absorbs changes into appropriate commit", function()
      if not harness.sl_available() then
        pending("sl not available")
        return
      end

      -- Check if absorb is available
      local absorb_check = vim.fn.system("cd " .. repo_path .. " && sl absorb --help 2>&1")
      if vim.v.shell_error ~= 0 or absorb_check:match("unknown command") then
        pending("sl absorb not available")
        return
      end

      -- Modify file1.txt (originally created in "First commit")
      -- Absorb should figure out this change belongs to the first commit
      harness.write_file("file1.txt", "absorbed content for file1")

      -- Use absorb_apply directly (absorb_with_preview uses vim.fn.confirm which blocks)
      stack.absorb_apply()

      -- Wait for absorb to complete - status should be clean
      local absorbed = vim.wait(3000, function()
        local status = vim.trim(vim.fn.system("cd " .. repo_path .. " && sl status"))
        return status == ""
      end, 200)

      assert.is_true(absorbed, "absorb should apply changes into appropriate commits (clean status)")
    end)
  end)
end)
