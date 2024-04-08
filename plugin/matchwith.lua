if vim.g.loaded_matchwith then
  return
end
vim.g.loaded_matchwith = true

local HL_ON_SCREEN = 'Matchwith'
local HL_OFF_SCREEN = 'MatchwithOut'
local fg1 = vim.api.nvim_get_hl(0, { name = 'MatchParen' }).fg
local fg2 = vim.api.nvim_get_hl(0, { name = 'Error' }).fg
local bg = vim.api.nvim_get_hl(0, { name = 'Normal' }).bg

_G.Matchwith_prepare = {
  highlights = {
    [HL_ON_SCREEN] = { fg = fg1, bg = bg, underline = true },
    [HL_OFF_SCREEN] = { fg = fg2, bg = bg, underline = true },
  },
  hlgroups = { [1] = HL_ON_SCREEN, [2] = HL_OFF_SCREEN },
}

for name, value in pairs(_G.Matchwith_prepare.highlights) do
  vim.api.nvim_set_hl(0, name, value)
end

vim.cmd('silent! NoMatchParen')
