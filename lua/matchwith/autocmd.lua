local M = {}
local helper = require('matchwith.helper')
local matchwith = require('matchwith.core')
local timer = require('matchwith.timer').set_timer()

---@param Cache Cache
---@return boolean
local function _is_enable(Cache)
  if Cache.disable == nil then
    Cache.disable = helper.is_enable_user_vars('matchwith_disable')
    if Cache.disable then
      vim.api.nvim_buf_clear_namespace(0, Cache.ns, 0, -1)
    end
  end
  return not Cache.disable
end

---Setup autocommands
---@param UNIQUE_NAME string
---@param Cache Cache
function M.setup(UNIQUE_NAME, Cache)
  local augroup = vim.api.nvim_create_augroup(UNIQUE_NAME, { clear = true })
  local with_unique_name = require('matchwith.util').name_formatter(UNIQUE_NAME)
  if not Cache.searchpairs then
    Cache:update_searchpairs()
  end

  vim.api.nvim_create_autocmd({ 'CursorMoved' }, {
    desc = with_unique_name('%s: update matchpair drawing'),
    group = augroup,
    callback = function()
      if _is_enable(Cache) then
        timer.debounce(vim.g.matchwith_debounce_time, function()
          matchwith.matching()
        end)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'CursorMovedI' }, {
    desc = with_unique_name('%s: update matchpair drawing'),
    group = augroup,
    callback = function()
      if _is_enable(Cache) then
        timer.debounce(vim.g.matchwith_debounce_time, function()
          matchwith.matching(true)
        end)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'CursorHold' }, {
    desc = with_unique_name('%s: reset disable matching'),
    group = augroup,
    callback = function()
      Cache.disable = nil
    end,
  })
  vim.api.nvim_create_autocmd({ 'WinScrolled' }, {
    desc = with_unique_name('%s: reset disable matching'),
    group = augroup,
    callback = function(ev)
      if _is_enable(Cache) and tonumber(ev.match) == Cache.winid then
        timer.debounce(vim.g.matchwith_debounce_time, function()
          local pos = vim.api.nvim_win_get_cursor(Cache.winid)
          if pos[1] - 1 == Cache.cur_row and pos[2] == Cache.cur_col then
            local session = matchwith:new()
            session:draw_markers(Cache.last.scope)
            session:draw_markers('parent')
          else
            matchwith.matching()
          end
        end)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'InsertEnter', 'InsertLeave' }, {
    desc = with_unique_name('%s: update matchpair drawing'),
    group = augroup,
    callback = function(ev)
      if _is_enable(Cache) then
        local is_insert_mode = ev.event == 'InsertEnter'
        matchwith.matching(is_insert_mode)
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufEnter', {
    desc = with_unique_name('%s: update buffer configrations'),
    group = augroup,
    callback = function(ev)
      Cache.disable = nil
      if _is_enable(Cache) then
        if vim.tbl_contains(vim.g.matchwith_ignore_buftypes, vim.bo.buftype) then
          vim.api.nvim_buf_set_var(ev.buf, 'matchwith_disable', true)
        else
          Cache:update_captures()
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
      if _is_enable(Cache) then
        local is_ignore_fuletype = vim.tbl_contains(vim.g.matchwith_ignore_filetypes, ev.match)
        if is_ignore_fuletype then
          vim.api.nvim_buf_set_var(ev.buf, 'matchwith_disable', true)
        else
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
