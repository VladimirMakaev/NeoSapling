--- Commit popup for NeoSapling.
--- Provides commit, amend, extend, uncommit, unamend, and absorb actions.
--- @module neosapling.popups.commit

local popup = require("neosapling.popups.builder")
local popups = require("neosapling.popups")
local actions = require("neosapling.popups.commit.actions")

local M = {}

--- Create and show the commit popup
---@return Buffer
function M.create()
  local p = popup.builder()
    :name("Commit")
    :group("Create")
      :action("c", "Commit", actions.commit)
    :group("Edit HEAD")
      :action("a", "Amend", actions.amend)
      :action("e", "Extend (no edit)", actions.extend)
      :action("E", "Metaedit", actions.metaedit)
    :group("Absorb")
      :action("A", "Absorb changes into stack", actions.absorb)
    :group("Undo")
      :action("u", "Uncommit", actions.uncommit)
      :action("U", "Unamend", actions.unamend)
    :group()
      :action("q", "Close", function() end)
      :action("<Esc>", "Close", function() end)
    :build()

  return popups.show(p)
end

return M
