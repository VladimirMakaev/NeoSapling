-- Minimal init for test isolation
-- This file is sourced by plenary for each test file
--
-- Only adds plugin and plenary to runtimepath - no user config or other plugins

-- Add plugin root to runtimepath
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Add plenary from tmp directory
vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/tmp/plenary")

-- Load plenary plugin
vim.cmd([[runtime! plugin/plenary.vim]])

-- Set common leader key default
vim.g.mapleader = " "
