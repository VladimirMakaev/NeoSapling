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
      :action("?", "Close help", function() end)
    :group("Navigation")
      :action("<Tab>", "Toggle fold/expand", function() end)
    :group()
      :action("q", "Close", function() end)
      :action("<Esc>", "Close", function() end)
    :build()

  return popups.show(p)
end

return M
