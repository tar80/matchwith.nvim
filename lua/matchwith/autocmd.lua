local M = {}
local helper = require('matchwith.helper')
local timer = require('matchwith.timer').set_timer()
local matchwith = require('matchwith.core')

---@param UNIQUE_NAME string
---@param Cache Cache
function M.setup(UNIQUE_NAME, Cache)
  local augroup = vim.api.nvim_create_augroup(UNIQUE_NAME, { clear = true })
  local with_unique_name = require('matchwith.util').name_formatter(UNIQUE_NAME)
  if not Cache.searchpairs then
    Cache:update_searchpairs()
  end

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    desc = with_unique_name('%s: update matchpair drawing'),
    group = augroup,
    callback = function()
      if not helper.is_enable_user_var('matchwith_disable') then
        timer.debounce(vim.g.matchwith_debounce_time, function()
          matchwith.matching()
        end)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'InsertEnter', 'InsertLeave' }, {
    desc = with_unique_name('%s: update matchpair drawing'),
    group = augroup,
    callback = function(ev)
      if not helper.is_enable_user_var('matchwith_disable') then
        local is_insert_mode = ev.event == 'InsertEnter'
        matchwith.matching(is_insert_mode)
        Cache.skip_matching = is_insert_mode
      end
    end,
  })
  vim.api.nvim_create_autocmd('WinEnter', {
    desc = with_unique_name('%s: update enable captures'),
    group = augroup,
    callback = function()
      if not helper.is_enable_user_var('matchwith_disable') then
        Cache:update_captures()
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufEnter', {
    desc = with_unique_name('%s: update buffer configrations'),
    group = augroup,
    callback = function()
      Cache.skip_matching = true
      if not helper.is_enable_user_var('matchwith_disable') then
        vim.b.matchwith_disable = vim.tbl_contains(vim.g.matchwith_ignore_buftypes, vim.bo.buftype)
        if not helper.is_enable_user_var('matchwith_disable') then
          Cache:update_searchpairs()
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufLeave', {
    desc = with_unique_name('%s: clear buffer configrations'),
    group = augroup,
    callback = function(ev)
      vim.api.nvim_buf_clear_namespace(ev.buf, Cache.ns, 0, -1)
      Cache:init()
    end,
  })
  vim.api.nvim_create_autocmd('Filetype', {
    desc = with_unique_name('%s: settings for each filetype'),
    group = augroup,
    callback = function(ev)
      if not helper.is_enable_user_var('matchwith_disable') then
        vim.b[ev.buf].matchwith_disable = vim.tbl_contains(vim.g.matchwith_ignore_filetypes, ev.match)
        if not helper.is_enable_user_var('matchwith_disable') then
          Cache:update_captures(ev.match)
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'OptionSet' }, {
    desc = with_unique_name('%s: reset searchpairs'),
    group = augroup,
    pattern = { 'matchpairs' },
    callback = function()
      Cache:update_searchpairs()
    end,
  })
  vim.api.nvim_create_autocmd({ 'OptionSet' }, {
    desc = with_unique_name('%s: reset listchars'),
    group = augroup,
    pattern = { 'listchars' },
    callback = function()
      Cache:update_wrap_marker()
    end,
  })
  vim.api.nvim_create_autocmd({ 'ColorScheme' }, {
    desc = with_unique_name('%s: reload hlgroups'),
    group = augroup,
    callback = function()
      helper.set_hl(Cache.hldetails)
    end,
  })
end

return M
