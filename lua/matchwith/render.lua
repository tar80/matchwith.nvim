local M = {}

---@private
local INDICATOR_DEFAULT = {
  relative = 'win',
  height = 1,
  focusable = false,
  noautocmd = true,
  border = false,
  style = 'minimal',
}

-- Show indicator on cursor
---@param ns integer
---@param text string
---@param timeout integer
---@param row integer
---@param col integer
---@return integer window_handle
function M.indicator(ns, text, timeout, row, col)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local opts = INDICATOR_DEFAULT
  opts.width = 1
  opts.row = 0
  opts.col = 0
  opts.bufpos = { row, col }
  local winid = vim.api.nvim_open_win(bufnr, false, opts)
  vim.api.nvim_win_set_hl_ns(winid, ns)
  vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, { text })
  vim.defer_fn(function()
    vim.api.nvim_win_close(winid, true)
  end, timeout)
  return winid
end

return M
