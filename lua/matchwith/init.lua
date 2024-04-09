local api = vim.api
local ts = vim.treesitter
local tsh = ts.highlighter
local util = require('matchwith.util')

local UNIQ_ID = 'Matchwith'
local HL_ON_SCREEN = _G.Matchwith_prepare.hlgroups[1]
local HL_OFF_SCREEN = _G.Matchwith_prepare.hlgroups[2]
_G.Matchwith_prepare.hlgroups = nil
local _default_options = {
  debounce_time = 80,
  ignore_filetypes = { 'help' },
  ignore_buftypes = { 'nofile' },
  captures = { 'keyword.function', 'keyword.repeat', 'keyword.conditional', 'punctuation.bracket' },
}

---@class Cache
local _cache = {
  last_state = {},
  ---startline = nil,
  ---endline = nil,
}

---@class Matchwith
local matchwith = {}
matchwith.ns = api.nvim_create_namespace(UNIQ_ID)
matchwith.augroup = vim.api.nvim_create_augroup(UNIQ_ID, {})
matchwith.opt = vim.tbl_extend('keep', _default_options, _G.Matchwith_prepare)
_G.Matchwith_prepare = nil

-- Start a new instance
function matchwith.new()
  local pos = api.nvim_win_get_cursor(0)
  local self = setmetatable({}, { __index = matchwith })
  self.mode = api.nvim_get_mode().mode
  self.bufnr = api.nvim_get_current_buf()
  self.filetype = api.nvim_get_option_value('filetype', { buf = self.bufnr })
  -- adjust row to zero-base
  self.top_row = util.zerobase(vim.fn.line('w0'))
  self.bottom_row = util.zerobase(vim.fn.line('w$'))
  self.cur_row = util.zerobase(pos[1])
  self.cur_col = pos[2]
  return self
end

-- Clear highlights for a matchpair
function matchwith.clear_ns(self)
  if _cache.startline and _cache.endline then
    api.nvim_buf_clear_namespace(0, self.ns, _cache.startline, _cache.endline)
    _cache.startline = nil
    _cache.endline = nil
  end
end

-- Convert range from Range4 to WordRange(row,scol,ecol)
---@param node TSNode|Range4
---@return WordRange
local function _adjust_range(node)
  local start_row, start_col, _, end_col = ts.get_node_range(node)
  return { start_row, start_col, end_col }
end

-- Illuminate a matchpair
function matchwith.illuminate(self)
  local highlighter = tsh.active[self.bufnr]
  if not highlighter then
    return
  end
  local ranges = {}
  highlighter.tree:for_each_tree(function(tree, ltree)
    if not tree then
      return
    end
    local tsroot = tree:root()
    local root_start_row, _, root_end_row, _ = tsroot:range()
    -- Only worry about trees within the line range
    if root_start_row > self.cur_row or root_end_row < self.cur_row then
      return
    end
    local tslang = ltree:lang()
    local query = highlighter:get_query(tslang):query()
    -- Some injected languages may not have highlight queries.
    if not query then
      return
    end
    local match, match_ranges = self:for_each_captures(tsroot, query, self.cur_row, self.cur_col, self.cur_col + 1)
    if match.node and match_ranges then
      local hlgroup, pair_range = self:get_matchpair(match, match_ranges)
      if not pair_range then
        return
      end
      local word_range = _adjust_range(match.range)
      pair_range = _adjust_range(pair_range)
      self:add_hl(hlgroup, word_range)
      self:add_hl(hlgroup, pair_range)
      ranges = { [1] = word_range, [2] = pair_range }
    end
  end)
  return ranges
end

-- Iteratively check if a node has a valid capture
function matchwith.for_each_captures(self, tsroot, query, row, scol, ecol)
  ---@type string, integer, TSNode?, Range4
  local _cpt, _ptn, tsnode, tsrange
  ---@type table<integer,{child:string,range:WordRange[]}>
  local match_ranges = {}
  local _cpts = self.opt.captures
  local iter = query:iter_matches(tsroot, self.bufnr, row, row + 1, { all = true })
  for pattern, matches in iter do
    for int, nodes in pairs(matches) do
      _cpt = query.captures[int]
      if vim.tbl_contains(_cpts, _cpt) then
        for _, node in ipairs(nodes) do
          local range = { node:range() }
          match_ranges[pattern] = util.tbl_insert(match_ranges, pattern, range)
          if row == range[1] then
            --TODO:feat cache system
            if (range[2] <= scol) and (range[4] >= ecol) then
              tsrange = range
              tsnode = node
              _ptn = pattern
              _cpts = { _cpt }
            end
          end
        end
      end
    end
  end
  return { node = tsnode, range = tsrange }, match_ranges[_ptn]
end

-- Whether the cursor position is at the node starting point
---@param cur_row integer
---@param parent Range4
---@param node Range4
---@return boolean is_start
local function _direction(cur_row, parent, node)
  if cur_row == parent[3] then
    if node[4] == parent[4] then
      return true
    end
    if parent[1] ~= parent[3] then
      return node[2] == parent[2]
    end
  end
  return false
end

-- Detect matchpair range
---@param next boolean
---@param node TSNode?
---@param ranges Range4[]
---@param count integer
---@return Range4|nil
local function _detect_node(next, node, ranges, count)
  for _ = 1, count, 1 do
    for _, range in ipairs(ranges) do
      if not node then
        return
      end
      if vim.deep_equal(range, {node:range()}) then
        return range
      end
    end
    node = next and node:next_sibling() or node:prev_sibling()
  end
end

-- Get hlgroup and pair range
function matchwith.get_matchpair(self, match, ranges)
  local hlgroup = HL_ON_SCREEN
  local parent = match.node:parent()
  if not parent then
    return hlgroup
  end
  local parent_range = { parent:range() }
  local count = parent:child_count() - 1
  _cache.startline = parent_range[1]
  _cache.endline = parent_range[3] + 1
  local is_start = _direction(self.cur_row, parent_range, match.range)
  -- Query.iter_matches may not be able to get the bracket range, so we need to add it
  if parent_range[1] ~= parent_range[3] then
    local t = is_start and { parent_range[1], parent_range[2], parent_range[1], parent_range[2] + 1 }
      or { parent_range[3], parent_range[4] - 1, parent_range[3], parent_range[4] }
    table.insert(ranges, t)
  end
  ---@type Range4|nil
  local pair_range
  if is_start then
    if parent_range[1] < self.top_row then
      hlgroup = HL_OFF_SCREEN
    end
    pair_range = _detect_node(true, parent:child(0), ranges, count)
  else
    if parent_range[3] > self.bottom_row then
      hlgroup = HL_OFF_SCREEN
    end
    pair_range = _detect_node(false, parent:child(count), ranges, count)
  end
  return hlgroup, pair_range
end

function matchwith.add_hl(self, hlgroup, word_range)
  api.nvim_buf_add_highlight(self.bufnr, self.ns, hlgroup, unpack(word_range))
end

-- Adjust columns if mode is insert mode
function matchwith.adjust_col(self, adjust)
  local col = self.cur_col
  if adjust then
    col = col - 1
  else
    local dec = (self.mode == 'i' or self.mode == 'R') and 1 or 0
    col = col - dec
  end
  self.cur_col = math.max(0, col)
end

-- Update matched pairs
function matchwith.matching(self, adjust)
  if vim.g.matchwith_disable or vim.b.matchwith_disable then
    return
  end
  if _cache.is_jump then
    _cache.is_jump = false
    return
  end
  local session = self:new()
  session:clear_ns()
  session:adjust_col(adjust)
  _cache.last_state = session:illuminate()
end

function matchwith.jumping(self)
  local vcount = vim.v.count1
  if vcount > 1 then
    vim.cmd(string.format('normal! %s%%', vcount))
    return
  end
  if vim.tbl_isempty(_cache.last_state) then
    vim.cmd('normal! %')
    return
  end
  local row, scol, ecol = unpack(_cache.last_state[2])

  local hlgroup = api.nvim_buf_get_extmarks(0, self.ns, { row, scol }, { row, ecol }, { details = true })[1][4].hl_group
  _cache.is_jump = hlgroup == HL_ON_SCREEN
  row = math.min(vim.fn.line('$'), row + 1)
  api.nvim_win_set_cursor(0, { row, scol })
  _cache.last_state = { _cache.last_state[2], _cache.last_state[1] }
end

-- Configure Matchwith settings
function matchwith.setup(opts)
  require('matchwith.config').set_options(opts)
end

---TODO: atode
---Get and set user-defined matchpairs
-- matchwith.set_matchpairs = function(self)
--   self.matchpairs = vim.tbl_map(function(v)
--     -- if not v:find('[([{]') then
--     return vim.split(v, ':', { plain = true })
--   end, vim.split(vim.bo[self.bufnr].matchpairs, ',', { plain = true }))
-- end

local timer = util.debounce(matchwith.opt.debounce_time, function()
  require('matchwith'):matching()
end)

util.autocmd({ 'CursorMoved', 'CursorMovedI' }, {
  group = matchwith.augroup,
  desc = 'Update matchpair highlight',
  callback = function()
    timer:start()
  end,
})

util.autocmd({ 'InsertEnter' }, {
  group = matchwith.augroup,
  desc = 'Update matchpair highlight',
  callback = function()
    require('matchwith'):matching(true)
  end,
})

util.autocmd({ 'InsertLeave' }, {
  group = matchwith.augroup,
  desc = 'Update matchpair highlight',
  callback = function()
    require('matchwith'):matching()
  end,
})

return matchwith
