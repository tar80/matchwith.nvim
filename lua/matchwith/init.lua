local M = {}
local UNIQUE_NAME = 'matchwith.nvim'

---@param opts Options
---@param force? boolean for debug
function M.setup(opts, force)
  if vim.g.loaded_matchwith and not force then
    return
  end
  local hl = require('matchwith.config').set_options(opts)
  require('matchwith.helper').set_hl(hl.details)
  local Cache = require('matchwith.cache'):setup(UNIQUE_NAME, hl)
  require('matchwith.autocmd').setup(UNIQUE_NAME, Cache)
  require('matchwith.keymap').setup(UNIQUE_NAME, Cache)
  if opts.jump_key then
    vim.cmd('silent! MatchDisable')
    vim.keymap.set({ 'n', 'x' }, opts.jump_key, function()
      require('matchwith.core'):jumping()
    end, { desc = ('%s: jump to matchpair'):format(UNIQUE_NAME) })
  end
  vim.cmd('silent! NoMatchParen')
end

return M
