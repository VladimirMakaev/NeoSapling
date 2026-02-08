--- Help popup for NeoSapling.
--- Shows available keybindings and actions.
--- @module neosapling.popups.help

local popup = require("neosapling.popups.builder")
local popups = require("neosapling.popups")

local M = {}

--- Create and show the help popup
---@return Buffer
function M.create()
  local p = popup.builder()
    :name("NeoSaplingHelp")
    :group("Popups")
      :action("c", "Commit...", function()
        require("neosapling.popups.commit").create()
      end)
      :action("d", "Diff...", function() end)
      :action("?", "Close help", function() end)
    :group("File Actions")
      :action("s", "Stage file", function() end)
      :action("u", "Unstage file", function() end)
      :action("x", "Discard changes/hunk", function() end)
    :group("Navigation")
      :action("<CR>", "Goto commit/bookmark", function() end)
      :action("<Tab>", "Toggle fold/expand", function() end)
      :action("{", "Previous section", function() end)
      :action("}", "Next section", function() end)
      :action("<C-r>", "Refresh", function() end)
      :action("p", "Pull from remote", function() end)
      :action("r", "Rebase...", function() end)
    :group("Stack Operations")
      :action("H", "Hide commit", function() end)
      :action("U", "Unhide commit", function() end)
      :action("G", "Graft commit", function() end)
    :group()
      :action("q", "Close", function() end)
      :action("<Esc>", "Close", function() end)
    :build()

  return popups.show(p)
end

return M
