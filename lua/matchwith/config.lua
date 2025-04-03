local M = {}
local validate = require('matchwith.compat').validate

local DEFAULT_MATCH = 'MatchParen'
local DEFAULT_MATCH_OUT = 'Error'
local DEFAULT_OPT = {
  alter_filetypes = { javascriptreact = 'javascript' },
  captures = {
    ['*'] = { 'keyword.function', 'keyword.repeat', 'keyword.conditional', 'punctuation.bracket', 'constructor' },
    off_side = { 'punctuation.bracket' },
  },
  debounce_time = 50,
  depth_limit = 10,
  ignore_filetypes = { 'vimdoc' },
  ignore_buftypes = { 'nofile' },
  indicator = 0,
  off_side = { 'query', 'fsharp', 'haskell', 'ocaml', 'make', 'nim', 'python', 'sass', 'scss', 'yaml' },
  priority = 100,
  show_next = false,
  show_parent = false,
  sign = false,
  symbols = { [1] = '↑', [2] = '↓', [3] = '→', [4] = '↗', [5] = '↘', [6] = '←', [7] = '↖', [8] = '↙' },
}

---@class HlGroups
---@field ON 'Matchwith'
---@field OFF 'MatchwithOut'
---@field NEXT_ON 'MatchwithNext'
---@field NEXT_OFF 'MatchwithNextOut'
---@field PARENT_ON 'MatchwithParent'
---@field PARENT_OFF 'MatchwithParentOut'
---@field SIGN 'MatchwithSign'
local HL_GROUPS = {
  ON = 'Matchwith',
  OFF = 'MatchwithOut',
  NEXT_ON = 'MatchwithNext',
  NEXT_OFF = 'MatchwithNextOut',
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
  [HL_GROUPS.OFF] = { sp = off_fg(), underline = true },
  [HL_GROUPS.NEXT_ON] = { sp = on_fg(), underline = true },
  [HL_GROUPS.NEXT_OFF] = { sp = off_fg(), underline = true },
  [HL_GROUPS.PARENT_ON] = { fg = on_fg(), bold = true },
  [HL_GROUPS.PARENT_OFF] = { fg = off_fg(), bold = true },
  [HL_GROUPS.SIGN] = { fg = on_fg(), bold = true },
}

---@param UNIQUE_NAME string
---@param opts Options User specified options
---@return {groups: HlGroups, details: {[string]:{fg:string,bg:string}}}
function M.set_options(UNIQUE_NAME, opts)
  opts = opts or {}
  validate('alter_filetypes', opts.alter_filetypes, 'table', true)
  validate('captures', opts.captures, 'table', true)
  validate('depth_limit', opts.depth_limit, 'number', true)
  validate('debounce_time', opts.debounce_time, 'number', true)
  validate('ignore_buftypes', opts.ignore_buftypes, 'table', true)
  validate('ignore_filetypes', opts.ignore_filetypes, 'table', true)
  validate('indicator', opts.indicator, 'number', true)
  validate('jump_key', opts.jump_key, 'string', true)
  validate('off_side', opts.off_side, 'table', true)
  validate('priority', opts.priority, 'number', true)
  validate('show_parent', opts.show_parent, 'boolean', true)
  validate('show_next', opts.show_next, 'boolean', true)
  validate('sign', opts.sign, 'boolean', true)
  validate('symbols', opts.symbols, 'table', true)

  vim.g.loaded_matchwith = true
  vim.g.matchwith_alter_filetypes = DEFAULT_OPT.alter_filetypes
  vim.g.matchwith_captures = DEFAULT_OPT.captures
  vim.g.matchwith_debounce_time = opts.debounce_time or DEFAULT_OPT.debounce_time
  vim.g.matchwith_depth_limit = (opts.depth_limit or DEFAULT_OPT.depth_limit) * 2
  vim.g.matchwith_ignore_buftypes = DEFAULT_OPT.ignore_buftypes
  vim.g.matchwith_ignore_filetypes = DEFAULT_OPT.ignore_filetypes
  vim.g.matchwith_indicator = opts.indicator or DEFAULT_OPT.indicator
  vim.g.matchwith_off_side = opts.off_side or DEFAULT_OPT.off_side
  vim.g.matchwith_priority = opts.priority or DEFAULT_OPT.priority
  vim.g.matchwith_show_next = opts.show_next or DEFAULT_OPT.show_next
  vim.g.matchwith_show_parent = opts.show_parent or DEFAULT_OPT.show_parent
  vim.g.matchwith_symbols = opts.symbols or DEFAULT_OPT.symbols
  if opts.captures then
    if vim.islist(opts.captures) then
      opts.captures = { ['*'] = opts.captures }
      vim.notify_once(
        [=[matchwith.nvim: The opts.captures specification has been changed from an array to a table with filetype as the key.]=],
        vim.log.levels.WARN,
        {}
      )
    end
    vim.g.matchwith_captures = vim.tbl_deep_extend('force', vim.g.matchwith_captures, opts.captures or {})
  end
  vim.g.matchwith_alter_filetypes = vim.list_extend(vim.g.matchwith_alter_filetypes, opts.alter_filetypes or {})
  vim.g.matchwith_ignore_buftypes = vim.list_extend(vim.g.matchwith_ignore_buftypes, opts.ignore_buftypes or {})
  vim.g.matchwith_ignore_filetypes = vim.list_extend(vim.g.matchwith_ignore_filetypes, opts.ignore_filetypes or {})
  vim.g.matchwith_off_side = vim.list_extend(vim.g.matchwith_off_side, opts.off_side or {})
  if opts.sign then
    vim.g.matchwith_sign = true
    hl_details[HL_GROUPS.SIGN] = hl_details[HL_GROUPS.SIGN]
  end
  if opts.jump_key then
    vim.cmd('silent! MatchDisable')
    vim.keymap.set({ 'n', 'x', 'o' }, opts.jump_key, function()
      require('matchwith.core'):jumping()
    end, { desc = ('%s: jump to matchpair'):format(UNIQUE_NAME) })
  end
  return { groups = HL_GROUPS, details = hl_details }
end

return M
