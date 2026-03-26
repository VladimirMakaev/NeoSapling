-- Buffer abstraction for NeoSapling UI
-- Manages named scratch buffers with lifecycle, atomic updates, and highlights
--
-- Source: Neogit buffer.lua pattern (see 02-RESEARCH.md)

local api = vim.api

---@class Buffer
---@field handle number Buffer handle (bufnr)
---@field namespace number Extmark namespace for highlights
---@field name string Buffer name (e.g., "neosapling://status")
local Buffer = {}
Buffer.__index = Buffer

--- Create or retrieve existing named buffer
---@param name string Buffer name (should start with neosapling://)
---@return Buffer
function Buffer:new(name)
  -- Check if buffer with this name already exists
  local existing = vim.fn.bufnr(name)
  local handle

  if existing ~= -1 then
    handle = existing
  else
    handle = api.nvim_create_buf(false, true) -- unlisted, scratch
    api.nvim_buf_set_name(handle, name)
  end

  local self = setmetatable({
    handle = handle,
    namespace = api.nvim_create_namespace("neosapling_" .. name),
    name = name,
  }, Buffer)

  self:_configure()
  return self
end

--- Configure buffer options for scratch buffer behavior
function Buffer:_configure()
  vim.bo[self.handle].buftype = "nofile"
  vim.bo[self.handle].bufhidden = "hide"
  vim.bo[self.handle].swapfile = false
  vim.bo[self.handle].modifiable = false
end

--- Check if buffer is still valid
---@return boolean
function Buffer:is_valid()
  return api.nvim_buf_is_valid(self.handle)
end

--- Set buffer lines atomically (single API call, no flicker)
---@param lines string[] Lines to set
function Buffer:set_lines(lines)
  if not self:is_valid() then
    return
  end
  vim.bo[self.handle].modifiable = true
  api.nvim_buf_set_lines(self.handle, 0, -1, false, lines)
  vim.bo[self.handle].modifiable = false
end

--- Clear all extmarks (highlights) from this buffer's namespace
function Buffer:clear_highlights()
  if not self:is_valid() then
    return
  end
  api.nvim_buf_clear_namespace(self.handle, self.namespace, 0, -1)
end

--- Add highlight to a range using extmarks
---@param line number 0-indexed line number
---@param col_start number Start column (0-indexed)
---@param col_end number End column (0-indexed, exclusive)
---@param hl_group string Highlight group name
function Buffer:add_highlight(line, col_start, col_end, hl_group)
  if not self:is_valid() then
    return
  end
  api.nvim_buf_set_extmark(self.handle, self.namespace, line, col_start, {
    end_col = col_end,
    hl_group = hl_group,
  })
end

--- Apply multiple highlights in a single batch
---@param highlights table[] Array of {line, col_start, col_end, hl, line_hl_group?, hl_eol?} entries
function Buffer:set_highlights(highlights)
  if not self:is_valid() then return end
  for _, hl in ipairs(highlights) do
    local extmark_opts = {
      end_col = hl.col_end,
      hl_group = hl.hl,
    }
    if hl.line_hl_group then
      extmark_opts.line_hl_group = hl.line_hl_group
    end
    if hl.hl_eol then
      extmark_opts.hl_eol = true
    end
    api.nvim_buf_set_extmark(self.handle, self.namespace, hl.line, hl.col_start, extmark_opts)
  end
end

--- Open buffer in a window
---@param kind? string Display kind: "split", "vsplit", "tab", "floating", "current" (default: "split")
---@return number? window Window handle (for floating windows)
function Buffer:show(kind)
  if not self:is_valid() then
    return nil
  end
  kind = kind or "split"

  if kind == "split" then
    vim.cmd("sbuffer " .. self.handle)
  elseif kind == "vsplit" then
    vim.cmd("vertical sbuffer " .. self.handle)
  elseif kind == "tab" then
    vim.cmd("tab sbuffer " .. self.handle)
  elseif kind == "current" then
    api.nvim_set_current_buf(self.handle)
  elseif kind == "floating" then
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)
    local win = api.nvim_open_win(self.handle, true, {
      relative = "editor",
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      style = "minimal",
      border = "rounded",
    })
    return win
  end
  return nil
end

--- Delete buffer and cleanup
function Buffer:destroy()
  if self:is_valid() then
    -- Clear namespace before deleting
    api.nvim_buf_clear_namespace(self.handle, self.namespace, 0, -1)
    api.nvim_buf_delete(self.handle, { force = true })
  end
end

--- Get buffer line count
---@return number
function Buffer:line_count()
  if not self:is_valid() then
    return 0
  end
  return api.nvim_buf_line_count(self.handle)
end

--- Get buffer lines
---@param start_line? number Start line (0-indexed, default 0)
---@param end_line? number End line (0-indexed, exclusive, default -1 for all)
---@return string[]
function Buffer:get_lines(start_line, end_line)
  if not self:is_valid() then
    return {}
  end
  start_line = start_line or 0
  end_line = end_line or -1
  return api.nvim_buf_get_lines(self.handle, start_line, end_line, false)
end

return Buffer
