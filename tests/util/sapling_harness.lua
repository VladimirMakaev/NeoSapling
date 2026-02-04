--- Sapling test harness utilities
--- Provides helpers for creating temporary Sapling repositories in tests
---
--- Usage:
---   local harness = require("tests.util.sapling_harness")
---   harness.in_prepared_repo(function(repo_path)
---     -- test code with isolated repo at repo_path
---   end)

local M = {}

-- Cache for sl availability check
local sl_available_cache = nil

--- Check if Sapling CLI (sl) is available
--- @return boolean true if sl command is available
function M.sl_available()
  if sl_available_cache ~= nil then
    return sl_available_cache
  end

  local result = vim.fn.system({ "sl", "--version" })
  sl_available_cache = vim.v.shell_error == 0
  return sl_available_cache
end

--- Create a temporary Sapling repository
--- @return string repo_path Path to the temporary repository
--- @return function cleanup_fn Function to call to remove the repository
function M.create_temp_repo()
  if not M.sl_available() then
    error("sl command not available - cannot create temp repo")
  end

  -- Create temp directory
  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, "p")

  -- Initialize Sapling repo
  local result = vim.fn.system({ "sl", "init", tmp_dir })
  if vim.v.shell_error ~= 0 then
    vim.fn.delete(tmp_dir, "rf")
    error("Failed to initialize Sapling repo: " .. result)
  end

  -- Create cleanup function
  local function cleanup()
    vim.fn.delete(tmp_dir, "rf")
  end

  return tmp_dir, cleanup
end

--- Add an initial commit to a repository
--- Creates a test.txt file and commits it
--- @param repo_path string Path to the repository
function M.with_initial_commit(repo_path)
  -- Create test file
  local test_file = repo_path .. "/test.txt"
  vim.fn.writefile({ "Initial content" }, test_file)

  -- Add and commit
  local cwd = vim.fn.getcwd()
  vim.fn.chdir(repo_path)

  vim.fn.system({ "sl", "add", test_file })
  if vim.v.shell_error ~= 0 then
    vim.fn.chdir(cwd)
    error("Failed to add file to repo")
  end

  vim.fn.system({ "sl", "commit", "-m", "Initial commit" })
  if vim.v.shell_error ~= 0 then
    vim.fn.chdir(cwd)
    error("Failed to create initial commit")
  end

  vim.fn.chdir(cwd)
end

--- Execute a test function with a prepared temporary repository
--- Automatically creates and cleans up the repository
--- @param test_fn function Function to call with repo_path as argument
function M.in_prepared_repo(test_fn)
  local repo_path, cleanup = M.create_temp_repo()

  local ok, err = pcall(test_fn, repo_path)

  -- Always clean up, even if test failed
  cleanup()

  -- Re-throw error if test failed
  if not ok then
    error(err, 0)
  end
end

--- Execute a test with a prepared repo that has an initial commit
--- @param test_fn function Function to call with repo_path as argument
function M.in_repo_with_commit(test_fn)
  M.in_prepared_repo(function(repo_path)
    M.with_initial_commit(repo_path)
    test_fn(repo_path)
  end)
end

return M
