local M = {}

function M.setup(opts, force)
  if vim.g.loaded_matchwith and not force then
    return
  end
  local UNIQUE_NAME = 'matchwith.nvim'
  local hl = require('matchwith.config').set_options(UNIQUE_NAME, opts)
  require('matchwith.helper').set_hl(hl.details)
  local Cache = require('matchwith.cache'):setup(UNIQUE_NAME, hl)
  require('matchwith.core').init_cache(Cache)
  require('matchwith.autocmd').setup(UNIQUE_NAME, Cache)
  require('matchwith.keymap').set_operator(UNIQUE_NAME, Cache)
  vim.cmd('silent! NoMatchParen')
end

return M
