-- Highlight group definitions for NeoSapling UI
-- Defines semantic highlight groups that respect user colorschemes
--
-- Source: Neogit hl.lua pattern (see 02-RESEARCH.md)

local api = vim.api

local M = {}

--- Default highlight group definitions
--- Links are used to respect colorscheme; explicit values are fallbacks
local highlight_groups = {
  -- Section headers (bold, for section titles like "Unstaged changes")
  NeoSaplingSection = { bold = true, link = "Title" },

  -- File status indicators
  NeoSaplingModified = { link = "DiffChange" }, -- M status
  NeoSaplingAdded = { link = "DiffAdd" }, -- A status
  NeoSaplingRemoved = { link = "DiffDelete" }, -- R status
  NeoSaplingUntracked = { link = "Comment" }, -- ? status

  -- UI elements
  NeoSaplingLabel = { bold = true, link = "Identifier" }, -- Labels like "Head:"
  NeoSaplingHash = { link = "Comment" }, -- Commit hashes (dim)

  -- Additional semantic groups
  NeoSaplingBranch = { link = "Keyword" }, -- Branch names
  NeoSaplingRemote = { link = "String" }, -- Remote names
  NeoSaplingHeader = { bold = true, link = "Statement" }, -- Buffer headers
  NeoSaplingSubtitle = { italic = true, link = "Comment" }, -- Subtitles/descriptions

  -- Popup UI elements
  NeoSaplingPopup = { link = "NormalFloat" },
  NeoSaplingPopupBorder = { link = "FloatBorder" },
  NeoSaplingPopupTitle = { bold = true, link = "Title" },
  NeoSaplingPopupHeading = { bold = true, link = "Statement" },
  NeoSaplingPopupKey = { link = "Special" },

  -- Staging status
  NeoSaplingStaged = { link = "DiffAdd" }, -- Staged files
  NeoSaplingUnstaged = { link = "DiffChange" }, -- Unstaged modified files

  -- Smartlog commit indicators
  NeoSaplingCurrent = { fg = "#3574B0", bold = true }, -- Current commit (@) - darker blue
  NeoSaplingObsolete = { link = "Comment" }, -- Obsolete commits (x)
  NeoSaplingAuthor = { link = "Comment" }, -- Commit author
  NeoSaplingDate = { link = "Comment" }, -- Commit date

  -- Hint bar (persistent key binding line at top of views)
  NeoSaplingHintKey = { bold = true, link = "Special" }, -- Key letters in hint bar
  NeoSaplingHintAction = { link = "Comment" }, -- Action descriptions in hint bar

  -- SSL smartlog metadata (Phabricator, signals, descriptions)
  NeoSaplingPhabDiff = { link = "Identifier" }, -- D12345 diff IDs
  NeoSaplingPhabStatus = { link = "String" }, -- Accepted, Needs Review, etc.
  NeoSaplingSignalPass = { fg = "#00aa00", link = "DiagnosticOk" }, -- ✓ signal passing
  NeoSaplingSignalFail = { fg = "#ff0000", link = "DiagnosticError" }, -- ✗ signal failing
  NeoSaplingLocalChanges = { link = "WarningMsg" }, -- (local changes) indicator
  NeoSaplingDesc = { link = "Normal" }, -- Commit message text

  -- Current commit line highlight (full-line dark blue background for @ commit)
  NeoSaplingCurrentLine = { bg = "#003366" },

  -- Neogit-style diff highlights (full-line background with hl_eol)
  NeoSaplingDiffAdd = { link = "DiffAdd" },
  NeoSaplingDiffDelete = { link = "DiffDelete" },
  NeoSaplingDiffHunkHeader = { link = "NeoSaplingSection" },
}

--- Check if a highlight group is already defined by user
---@param name string Highlight group name
---@return boolean
local function is_user_defined(name)
  local ok, existing = pcall(api.nvim_get_hl, 0, { name = name })
  return ok and not vim.tbl_isempty(existing)
end

--- Setup all NeoSapling highlight groups
--- Always sets plugin highlights. Users can override after setup() in their config.
--- Also registers a ColorScheme autocmd to re-apply after theme changes.
function M.setup()
  M._apply()

  -- Re-apply when colorscheme changes (themes clear all highlights)
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("NeoSaplingHighlights", { clear = true }),
    callback = function()
      M._apply()
    end,
  })
end

--- Apply all highlight definitions
function M._apply()
  for name, definition in pairs(highlight_groups) do
    if definition.link then
      api.nvim_set_hl(0, name, { link = definition.link })
    else
      api.nvim_set_hl(0, name, definition)
    end
  end
end

--- Get list of all defined highlight group names
---@return string[]
function M.get_groups()
  local groups = {}
  for name, _ in pairs(highlight_groups) do
    table.insert(groups, name)
  end
  table.sort(groups)
  return groups
end

return M
