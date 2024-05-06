local matchwith = require('matchwith')

local M = {}

---@param opts Options Global options
---@return boolean is_ok
function M.set_options(opts)
  if not opts then
    return false
  end
  vim.validate({
    debounce_time = { opts.debounce_time, 'number', true },
    ignore_filetypes = { opts.ignore_filetypes, 'table', true },
    ignore_buftypes = { opts.ignore_buftypes, 'table', true },
    jump_key = { opts.jump_key, 'string', true },
    captures = { opts.captures, 'table', true },
    indicator = { opts.indicator, 'number', true },
    sign = { opts.sign, 'boolean', true },
    symbols = { opts.symbols, 'table', true },
  })
  if opts.debounce_time then
    vim.g.matchwith_debounce_time = opts.debounce_time
  end
  if opts.ignore_filetypes then
    vim.list_extend(vim.g.matchwith_ignore_filetypes, opts.ignore_filetypes)
  end
  if opts.ignore_buftypes then
    vim.list_extend(vim.g.matchwith_ignore_buftypes, opts.ignore_buftypes)
  end
  if opts.captures then
    vim.list_extend(vim.g.matchwith_captures, opts.captures)
  end
  if opts.jump_key then
    vim.cmd('silent! MatchDisable')
    vim.keymap.set({ 'n', 'x', 'o' }, opts.jump_key, function()
      return '<Cmd>lua require("matchwith").jumping()<CR>'
    end, { expr = true, desc = 'Jump cursor to matchpair' })
  end
  if opts.indicator and (opts.indicator > 0) then
    local name = 'NormalFloat'
    local value = { link = matchwith.hlgroups.off }
    vim.api.nvim_set_hl(matchwith.ns, name, value)
    vim.g.matchwith_indicator = opts.indicator
  end
  if opts.sign then
    local name = matchwith.hlgroups.sign
    local fg = vim.api.nvim_get_hl(0, { name = matchwith.hlgroups.off }).fg
    local value = { default = true, fg = fg, bold = true }
    vim.api.nvim_set_hl(0, name, value)
    vim.g.matchwith_sign = opts.sign
  end
  if opts.symbols then
    vim.g.symbols = opts.symbols
  end
  return true
end

return M
