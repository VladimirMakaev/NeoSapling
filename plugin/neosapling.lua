-- NeoSapling plugin commands
-- This file is auto-loaded by Neovim from plugin/ directory

vim.api.nvim_create_user_command("NeoSapling", function(opts)
  -- Ensure plugin is set up
  local neosapling = require("neosapling")
  if not neosapling.config then
    neosapling.setup()
  end

  require("neosapling.status").open()
end, {
  desc = "Open NeoSapling status view",
})
