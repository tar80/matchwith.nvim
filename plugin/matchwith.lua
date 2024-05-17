if vim.g.loaded_matchwith then
  return
end

vim.g.loaded_matchwith = true

local UNIQ_ID = 'Matchwith-nvim'
local HLGROUP = {
  on = 'Matchwith',
  off = 'MatchwithOut',
  sign = 'MatchwithSign',
}
local hl_detail = {
  [HLGROUP.on] = { default = true, fg = vim.api.nvim_get_hl(0, { name = 'MatchParen' }).fg, bg = 'NONE' },
  [HLGROUP.off] = { default = true, fg = vim.api.nvim_get_hl(0, { name = 'Error' }).fg, bg = 'NONE' },
}

local util = require('fret.util')
local timer = util.set_timer()
local augroup = vim.api.nvim_create_augroup(UNIQ_ID, { clear = true })

_G.Matchwith_hlgroup = HLGROUP
vim.g.matchwith_debounce_time = 100
vim.g.matchwith_indicator = 0
vim.g.matchwith_sign = false
vim.g.matchwith_ignore_filetypes = { 'vimdoc' }
vim.g.matchwith_ignore_buftypes = { 'nofile' }
vim.g.matchwith_captures = { 'keyword.function', 'keyword.repeat', 'keyword.conditional', 'punctuation.bracket' }
vim.g.matchwith_symbols =
  { [1] = '↑', [2] = '↓', [3] = '→', [4] = '↗', [5] = '↘', [6] = '←', [7] = '↖', [8] = '↙' }

local function set_hl()
  for name, value in pairs(hl_detail) do
    vim.api.nvim_set_hl(0, name, value)
  end
end

util.autocmd('BufEnter', {
  desc = 'Matchwith ignore buftypes',
  group = augroup,
  callback = function()
    if vim.b.matchwith_disable or (vim.bo.buftype ~= '') then
      return
    end
    vim.b.matchwith_disable = vim.tbl_contains(vim.g.matchwith_ignore_buftypes, vim.bo.buftype)
    require('matchwith').clear_userdef()
  end,
})

util.autocmd({ 'CursorMoved', 'CursorMovedI' }, {
  desc = 'Update matchpair highlight',
  group = augroup,
  callback = function()
    timer.debounce(vim.g.matchwith_debounce_time, function()
      require('matchwith').matching()
    end)
  end,
})

util.autocmd({ 'InsertEnter', 'InsertLeave' }, {
  desc = 'Update matchpair highlight',
  group = augroup,
  callback = function()
    require('matchwith').matching()
  end,
})

util.autocmd({ 'OptionSet' }, {
  desc = 'Reset matchwith userdef',
  group = augroup,
  pattern = { 'matchpairs' },
  callback = function()
    require('matchwith').set_userdef()
  end,
})

util.autocmd({ 'ColorScheme' }, {
  desc = 'Reload matchwith hlgroups',
  group = augroup,
  callback = function()
    set_hl()
  end,
}, true)

vim.cmd('silent! NoMatchParen')
set_hl()
