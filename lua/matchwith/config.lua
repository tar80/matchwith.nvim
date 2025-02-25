local M = {}
local validate = require('matchwith.compat').validate

local DEFAULT_MATCH = 'MatchParen'
local DEFAULT_MATCH_OUT = 'Error'
local DEFAULT_OPT = {
  debounce_time = 100,
  indicator = 0,
  sign = false,
  ignore_filetypes = { 'vimdoc' },
  ignore_buftypes = { 'nofile' },
  captures = { 'keyword.function', 'keyword.repeat', 'keyword.conditional', 'punctuation.bracket', 'constructor' },
  symbols = { [1] = '↑', [2] = '↓', [3] = '→', [4] = '↗', [5] = '↘', [6] = '←', [7] = '↖', [8] = '↙' },
}

---@class HlGroups
---@field ON 'Matchwith'
---@field OFF 'MatchwithOut'
---@field SIGN 'MatchwithSign'
local HL_GROUPS = {
  ON = 'Matchwith',
  OFF = 'MatchwithOut',
  SIGN = 'MatchwithSign',
}

local on_fg = function()
  local fg = vim.api.nvim_get_hl(0, { name = DEFAULT_MATCH }).fg
  return { fg = fg, sp = fg }
end
local off_fg = function()
  local fg = vim.api.nvim_get_hl(0, { name = DEFAULT_MATCH_OUT }).fg
  return { fg = fg, sp = fg }
end
local hl_details = {
  [HL_GROUPS.ON] = on_fg,
  [HL_GROUPS.OFF] = off_fg,
}

---@param opts Options User specified options
---@return {groups: HlGroups, details: {[string]:{fg:string,bg:string}}}?
function M.set_options(opts)
  if not opts then
    return
  end
  validate('captures', opts.captures, 'table', true)
  validate('ignore_buftypes', opts.ignore_buftypes, 'table', true)
  validate('ignore_filetypes', opts.ignore_filetypes, 'table', true)
  validate('debounce_time', opts.debounce_time, 'number', true)
  validate('indicator', opts.indicator, 'number', true)
  validate('jump_key', opts.jump_key, 'string', true)
  validate('sign', opts.sign, 'boolean', true)
  validate('symbols', opts.symbols, 'table', true)

  vim.g.loaded_matchwith = true
  vim.g.matchwith_captures = DEFAULT_OPT.captures
  vim.g.matchwith_ignore_buftypes = DEFAULT_OPT.ignore_buftypes
  vim.g.matchwith_ignore_filetypes = DEFAULT_OPT.ignore_filetypes
  vim.g.matchwith_debounce_time = opts.debounce_time or DEFAULT_OPT.debounce_time
  vim.g.matchwith_indicator = opts.indicator or DEFAULT_OPT.indicator
  vim.g.matchwith_symbols = opts.symbols or DEFAULT_OPT.symbols
  vim.list_extend(vim.g.matchwith_captures, opts.captures or {})
  vim.list_extend(vim.g.matchwith_ignore_buftypes, opts.ignore_buftypes or {})
  vim.list_extend(vim.g.matchwith_ignore_filetypes, opts.ignore_filetypes or {})
  if vim.g.matchwith_indicator > 0 then
    hl_details['NormalFloat'] = hl_details[HL_GROUPS.OFF]
  end
  if opts.sign then
    vim.g.matchwith_sign = true
    hl_details[HL_GROUPS.SIGN] = hl_details[HL_GROUPS.OFF]
  end
  if opts.jump_key then
    vim.cmd('silent! MatchDisable')
    vim.keymap.set({ 'n', 'x', 'o' }, opts.jump_key, function()
      require('matchwith'):jumping()
    end, { desc = 'Matchwith jump to matchpair' })
  end
  return { groups = HL_GROUPS, details = hl_details }
end

return M
