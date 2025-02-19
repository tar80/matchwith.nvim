local M = {}

local DEFAULT_MATCH = 'MatchParen'
local DEFAULT_MATCH_OUT = 'Error'

---@class HlGroups
---@field ON 'Matchwith'
---@field OFF 'MatchwithOut'
---@field SIGN 'MatchwithSign'
---@field PARENT_ON 'MatchwithParent'
---@field PARENT_OUT 'MatchwithParentOUT'
local HL_GROUPS = {
  ON = 'Matchwith',
  OFF = 'MatchwithOut',
  PARENT_ON = 'MatchwithParent',
  PARENT_OFF = 'MatchwithParentOut',
  SIGN = 'MatchwithSign',
}
local on_fg = function()
  return vim.api.nvim_get_hl(0, { name = DEFAULT_MATCH }).fg
end
local off_fg = function()
  return vim.api.nvim_get_hl(0, { name = DEFAULT_MATCH_OUT }).fg
end
local hl_details = {
  [HL_GROUPS.ON] = { sp = on_fg(), underline = true },
  [HL_GROUPS.OFF] = { sp = off_fg(), underdouble = true },
  [HL_GROUPS.PARENT_ON] = { fg = on_fg() },
  [HL_GROUPS.PARENT_OFF] = { fg = off_fg() },
}
---@param opts Options User options
---@return {groups: HlGroups, details: {[string]:{fg:string,bg:string}}}?
function M.set_options(opts)
  if not opts then
    return
  end
  vim.g.loaded_matchwith = true
  vim.g.matchwith_debounce_time = 100
  vim.g.matchwith_depth_limit = 10
  vim.g.matchwith_indicator = 0
  vim.g.matchwith_sign = false
  vim.g.matchwith_show_parent = true
  vim.g.matchwith_show_next = true
  vim.g.matchwith_ignore_filetypes = { 'vimdoc' }
  vim.g.matchwith_ignore_buftypes = { 'nofile' }
  vim.g.matchwith_captures =
    { 'keyword.function', 'keyword.repeat', 'keyword.conditional', 'punctuation.bracket', 'constructor' }
  vim.g.matchwith_symbols =
    { [1] = '↑', [2] = '↓', [3] = '→', [4] = '↗', [5] = '↘', [6] = '←', [7] = '↖', [8] = '↙' }

  vim.validate('debounce_time', opts.debounce_time, 'number', true)
  vim.validate('depth_limit', opts.depth_limit, 'number', true)
  vim.validate('ignore_filetypes', opts.ignore_filetypes, 'table', true)
  vim.validate('ignore_buftypes', opts.ignore_buftypes, 'table', true)
  vim.validate('jump_key', opts.jump_key, 'string', true)
  vim.validate('captures', opts.captures, 'table', true)
  vim.validate('indicator', opts.indicator, 'number', true)
  vim.validate('sign', opts.sign, 'boolean', true)
  vim.validate('show_parent', opts.show, 'boolean', true)
  vim.validate('show_next', opts.show, 'boolean', true)
  vim.validate('symbols', opts.symbols, 'table', true)
  if opts.debounce_time then
    vim.g.matchwith_debounce_time = opts.debounce_time
  end
  if opts.depth_limit then
    vim.g.matchwith_depth_limit = opts.depth_limit
  end
  if opts.ignore_filetypes then
    vim.g.matchwith_ignore_filetypes = vim.list_extend(vim.g.matchwith_ignore_filetypes, opts.ignore_filetypes)
  end
  if opts.ignore_buftypes then
    vim.g.matchwith_ignore_buftypes = vim.list_extend(vim.g.matchwith_ignore_buftypes, opts.ignore_buftypes)
  end
  if opts.captures then
    vim.list_extend(vim.g.matchwith_captures, opts.captures)
  end
  if opts.jump_key then
    vim.cmd('silent! MatchDisable')
    vim.keymap.set({ 'n', 'x', 'o' }, opts.jump_key, function()
      return '<Cmd>lua require("matchwith").jumping()<CR>'
    end, { expr = true, desc = 'Matchwith jump to target' })
  end
  if opts.indicator and (opts.indicator > 0) then
    hl_details['NormalFloat'] = hl_details[HL_GROUPS.PARENT_OFF]
    vim.g.matchwith_indicator = opts.indicator
  end
  if opts.sign then
    hl_details[HL_GROUPS.SIGN] = hl_details[HL_GROUPS.PARENT_OFF]
    vim.g.matchwith_sign = opts.sign
  end
  if opts.show_parent then
    vim.g.matchwith_show_parent = opts.show_parent
  end
  if opts.show_next then
    vim.g.matchwith_show_next = opts.show_next
  end
  if opts.symbols then
    vim.g.symbols = opts.symbols
  end
  return { groups = HL_GROUPS, details = hl_details }
end

return M
