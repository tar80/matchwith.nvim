---@class Cache
local M = {}
local helper = require('matchwith.helper')

function M:setup(UNIQUE_NAME, hl)
  self.ns = vim.api.nvim_create_namespace(UNIQUE_NAME)
  self.hlgroups = hl.groups
  self.hldetails = hl.details
  self.hl = {
    cur = { on = hl.groups.ON, off = hl.groups.OFF },
    next = { on = hl.groups.NEXT_ON, off = hl.groups.NEXT_OFF },
    parent = { on = hl.groups.PARENT_ON, off = hl.groups.PARENT_OFF },
  }
  self.markers = { cur = { 1, 2 }, next = { 1, 2 }, parent = { 3, 4 } }
  self:update_wrap_marker()
  self:update_captures()
  self:init()
  return self
end

local _initial_values = {
  changetick = 0,
  skip_matching = false,
  last = {},
}

function M:init()
  vim.iter(_initial_values):each(function(key, value)
    self[key] = value
  end)
end

function M:update_captures(filetype)
  filetype = filetype or vim.api.nvim_get_option_value('filetype', {})
  local language = vim.treesitter.language.get_lang(filetype)
  local lang_captures = vim.g.matchwith_captures
  local match_captures = lang_captures[language]
  if match_captures then
    self.captures = match_captures
  else
    self.captures = lang_captures['*']
  end
end

function M:update_searchpairs()
  local chrs, matchpair = {}, {}
  local matchpairs = helper.split_option_value('matchpairs', { scope = 'local' })
  if matchpairs[1] ~= '' then
    vim.tbl_map(function(v)
      ---@type string,string
      local s, e = unpack(vim.split(v, ':', { plain = true }))
      local adjust_s = s == '[' and '\\[' or s
      local adjust_e = e == ']' and '\\]' or e
      matchpair[s] = { adjust_s, '', adjust_e, 'nW' }
      matchpair[e] = { adjust_s, '', adjust_e, 'bnW' }
      vim.list_extend(chrs, { s, e })
    end, helper.split_option_value('matchpairs', { scope = 'local' }))
  end
  self.searchpairs = { chrs = chrs, matchpair = matchpair }
end

function M:update_wrap_marker()
  self.extends, self.precedes = helper.get_wrap_marker_flags()
end

return M
