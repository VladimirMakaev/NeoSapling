-- Test entry point for NeoSapling
-- Invoked by `make test` via nvim --headless -S tests/init.lua
--
-- This file sets up the test environment and runs all specs through plenary.

-- Add plugin root to runtimepath
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Add plenary from tmp directory
vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/tmp/plenary")

-- Load plenary plugin
vim.cmd([[runtime! plugin/plenary.vim]])

-- Get test directory from environment or use default
local test_dir = vim.env.TEST_FILES or "tests/specs"

-- Run tests with plenary harness
require("plenary.test_harness").test_directory(test_dir, {
  minimal_init = "tests/minimal_init.lua",
  sequential = true,
})
