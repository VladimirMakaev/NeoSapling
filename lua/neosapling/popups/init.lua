--- Popup registry and display module for NeoSapling.
--- Shows floating windows with key dispatch for popup actions.
--- @module neosapling.popups

local ui = require("neosapling.lib.ui")

local M = {}

-- Active popup state
local active_popup = nil

--- Render popup definition to component tree
---@param definition PopupDefinition
---@return Component
local function render_popup(definition)
  local children = {}

  -- Header
  table.insert(children, ui.row({
    ui.text(definition.name, { hl = "NeoSaplingPopupTitle" }),
  }))
  table.insert(children, ui.text(""))

  -- Groups
  for _, group in ipairs(definition.groups) do
    if group.heading then
      table.insert(children, ui.row({
        ui.text(group.heading, { hl = "NeoSaplingPopupHeading" }),
      }))
    end

    for _, action in ipairs(group.actions) do
      local key_display = table.concat(action.keys, "/")
      table.insert(children, ui.row({
        ui.text("  ", {}),
        ui.text(key_display, { hl = "NeoSaplingPopupKey" }),
        ui.text("  ", {}),
        ui.text(action.description, {}),
      }))
    end

    table.insert(children, ui.text(""))
  end

  return ui.col(children)
end

--- Calculate popup dimensions based on content
---@param lines string[]
---@return number width, number height
local function calculate_dimensions(lines)
  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, #line)
  end
  -- Add padding
  return max_width + 4, #lines + 2
end

--- Setup buffer-local keymaps for popup
---@param buffer Buffer
---@param definition PopupDefinition
function M._setup_keymaps(buffer, definition)
  local bufnr = buffer.handle

  -- Map all actions
  for _, group in ipairs(definition.groups) do
    for _, action in ipairs(group.actions) do
      for _, key in ipairs(action.keys) do
        vim.keymap.set("n", key, function()
          M.close()
          action.callback()
        end, { buffer = bufnr, nowait = true, silent = true })
      end
    end
  end

  -- Always allow q and Escape to close (may override action mappings, that's intentional)
  vim.keymap.set("n", "q", M.close, { buffer = bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", M.close, { buffer = bufnr, nowait = true, silent = true })
end

--- Show popup in floating window
---@param definition PopupDefinition
---@return Buffer
function M.show(definition)
  -- Close any existing popup (prevent stacking)
  M.close()

  -- Create buffer
  local buffer = ui.Buffer:new("neosapling://popup/" .. definition.name)

  -- Render content
  local tree = render_popup(definition)
  local result = ui.render(tree)
  buffer:set_lines(result.lines)

  -- Apply highlights
  buffer:clear_highlights()
  for _, hl in ipairs(result.highlights) do
    buffer:add_highlight(hl.line, hl.col_start, hl.col_end, hl.hl)
  end

  -- Calculate dimensions
  local width, height = calculate_dimensions(result.lines)

  -- Open floating window centered in editor
  local win = vim.api.nvim_open_win(buffer.handle, true, {
    relative = "editor",
    width = math.min(width, math.floor(vim.o.columns * 0.8)),
    height = math.min(height, math.floor(vim.o.lines * 0.6)),
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. definition.name .. " ",
    title_pos = "center",
  })

  -- Setup keymaps
  M._setup_keymaps(buffer, definition)

  -- Track active popup
  active_popup = { buffer = buffer, window = win }

  return buffer
end

--- Close active popup
function M.close()
  if active_popup then
    if vim.api.nvim_win_is_valid(active_popup.window) then
      vim.api.nvim_win_close(active_popup.window, true)
    end
    if active_popup.buffer:is_valid() then
      active_popup.buffer:destroy()
    end
    active_popup = nil
  end
end

return M
