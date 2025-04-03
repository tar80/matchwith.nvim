---@class Cache
local M = {}
local helper = require('matchwith.helper')

local _initial_values = {
  changetick = 0,
  skip_matching = false,
  last = {},
}

function M:setup(UNIQUE_NAME, hl)
  self.ns = vim.api.nvim_create_namespace(UNIQUE_NAME)
  self.hlgroups = hl.groups
  self.hldetails = hl.details
  self.markers = { cur = { 1, 2 }, next = { 1, 2 }, parent = { 3, 4 } }
  self.hl = {
    cur = { on = hl.groups.ON, off = hl.groups.OFF },
    next = { on = hl.groups.NEXT_ON, off = hl.groups.NEXT_OFF },
    parent = { on = hl.groups.PARENT_ON, off = hl.groups.PARENT_OFF },
  }
  self:update_wrap_marker()
  self:update_captures()
  self:init()
  return self
end

function M:init()
  vim.iter(_initial_values):each(function(key, value)
    self[key] = value
  end)
end

function M:update_captures(filetype)
  filetype = filetype or vim.api.nvim_get_option_value('filetype', {})
  filetype = vim.g.matchwith_alter_filetypes[filetype] or filetype
  local ft_captures = vim.g.matchwith_captures
  local off_side = vim.g.matchwith_off_side
  local match_captures = ft_captures[filetype]
  if match_captures then
    self.captures = match_captures
  elseif vim.tbl_contains(off_side, filetype, {}) then
    self.captures = ft_captures['off_side']
  else
    self.captures = ft_captures['*']
  end
end

function M:update_searchpairs()
  local chrs, matchpair = {}, {}
  vim.tbl_map(function(v)
    ---@type string,string
    local s, e = unpack(vim.split(v, ':', { plain = true }))
    local adjust_s = s == '[' and '\\[' or s
    local adjust_e = e == ']' and '\\]' or e
    matchpair[s] = { adjust_s, '', adjust_e, 'nW' }
    matchpair[e] = { adjust_s, '', adjust_e, 'bnW' }
    vim.list_extend(chrs, { s, e })
  end, helper.split_option_value('matchpairs', { scope = 'local' }))
  self.searchpairs = { chrs = chrs, matchpair = matchpair }
end

function M:update_wrap_marker()
  self.extends, self.precedes = helper.get_wrap_marker_flags()
end

return M
