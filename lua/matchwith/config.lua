local matchwith = require('matchwith')
local util = require('matchwith.util')

local UNIQ_ID = 'Matchwith/config'
local M = {}

---@param opts Options Global options
function M.set_options(opts)
  if not opts then
    util.notify(UNIQ_ID, 'Error: Requires arguments', vim.log.levels.ERROR)
    return
  end

  vim.validate({
    debounce_time = { opts.debounce_time, 'number', true },
    ignore_filetypes = { opts.ignore_filetypes, 'table', true },
    ignore_buftypes = { opts.ignore_buftypes, 'table', true },
    jump_key = { opts.jump_key, 'string', true },
    captures = { opts.captures, 'table', true },
    highlights = { opts.highlights, 'table', true },
  })

  if opts.debounce_time then
    matchwith.opt.debounce_time = opts.debounce_time
  end
  if opts.ignore_filetypes then
    vim.list_extend(matchwith.opt.ignore_filetypes, opts.ignore_filetypes)
    M.set_ignore_autocmd('FileType', 'filetype')
  end
  if opts.ignore_buftypes then
    vim.list_extend(matchwith.opt.ignore_buftypes, opts.ignore_buftypes)
    M.set_ignore_autocmd('BufEnter', 'buftype')
  end
  if opts.highlights then
    matchwith.opt.highlights = vim.tbl_extend('force', matchwith.opt.highlights, opts.highlights)
    matchwith:set_hl()
  end
  if opts.captures then
    vim.list_extend(matchwith.opt.captures, opts.captures)
  end
  if opts.jump_key then
    matchwith.opt.jump_key = opts.jump_key
    vim.cmd('silent! MatchDisable')
    vim.keymap.set({ 'n', 'x', 'o' }, opts.jump_key, function()
      return '<Cmd>lua require("matchwith"):jumping()<CR>'
    end, { expr = true, desc = 'Jump cursor to matchpair' })
  end
end

---Set variable to disable Matchwith on buffer
---@param name string
---@param typeish 'filetype'|'buftype'
M.set_ignore_autocmd = function(name, typeish)
  util.autocmd(name, {
    group = matchwith.augroup,
    callback = function()
      if vim.b.matchwith_disable or vim.bo[typeish] == '' then
        return
      end
      local ignore_items = matchwith.opt[string.format('ignore_%ss', typeish)] --[=[@as string[]]=]
      ---@type boolean
      vim.b.matchwith_disable = vim.tbl_contains(ignore_items, vim.bo[typeish])
    end,
    desc = string.format('Ignore %s', typeish),
  })
end

return M
