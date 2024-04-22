---@module 'util'
local util = require('matchwith.util')
local api = vim.api
local fn = vim.fn
local ts = vim.treesitter
local tsq = ts.query

local UNIQ_ID = 'Matchwith'
local DEFALUT_OPTIONS = {
  debounce_time = 100,
  indicator = 0,
  ignore_filetypes = { 'vimdoc' },
  ignore_buftypes = { 'nofile' },
  captures = { 'keyword.function', 'keyword.repeat', 'keyword.conditional', 'punctuation.bracket' },
}
local DIR_SIGN =
  { [1] = '↑', [2] = '↓', [3] = '→', [4] = '↗', [5] = '↘', [6] = '←', [7] = '↖', [8] = '↙' }
local HL_ON_SCREEN = _G.Matchwith_prepare.hlgroups[1]
local HL_OFF_SCREEN = _G.Matchwith_prepare.hlgroups[2]
_G.Matchwith_prepare.hlgroups = nil

local _cache = {
  last = { row = vim.NIL, state = {}, line = {} },
  marker_range = {},
  skip_matching = false,
  changetick = 0,
}
---@class Cache
local cache = vim.deepcopy(_cache)

---@class Matchwith
local matchwith = {}
matchwith.ns = api.nvim_create_namespace(UNIQ_ID)
matchwith.augroup = api.nvim_create_augroup(UNIQ_ID, {})
matchwith.timer = util.set_timer()
matchwith.opt = vim.tbl_extend('keep', DEFALUT_OPTIONS, _G.Matchwith_prepare)
_G.Matchwith_prepare = nil

-- Adjust column for insert-mode
---@package
---@param mode string
---@param col integer
---@return integer column
local function _adjust_col(mode, col)
  local dec = util.is_insert_mode(mode) and 1 or 0
  return math.max(0, col - dec)
end

-- Convert range from Range4 to WordRange(row,scol,ecol)
---@package
---@param node TSNode|Range4
---@return WordRange WordRange
local function _convert_range(node)
  local row, scol, _, ecol = ts.get_node_range(node)
  return { row, scol, ecol }
end

-- Start a new instance
function matchwith.new(row, col)
  local self = setmetatable({}, { __index = matchwith })
  self['mode'] = api.nvim_get_mode().mode
  self['bufnr'] = api.nvim_get_current_buf()
  self['winid'] = api.nvim_get_current_win()
  self['filetype'] = api.nvim_get_option_value('filetype', { buf = self.bufnr })
  self['changetick'] = api.nvim_buf_get_changedtick(self.bufnr)
  local pos = api.nvim_win_get_cursor(self.winid)
  -- adjust row to zero-base
  self['top_row'] = util.zerobase(fn.line('w0'))
  self['bottom_row'] = util.zerobase(fn.line('w$'))
  self['cur_row'] = row or util.zerobase(pos[1])
  self['cur_col'] = col or _adjust_col(self.mode, pos[2])
  return self
end

-- Clear highlights for a matchpair
function matchwith.clear_ns(self)
  local clear = false
  if not vim.tbl_isempty(cache.marker_range) then
    api.nvim_buf_clear_namespace(0, self.ns, 0, -1)
    clear = true
  end
  return clear
end

---Get match items
function matchwith.get_matches(self)
  ---@type MatchItem?, Range4[], Range4[]
  local match, ranges, line = nil, {}, {}
  local ok, lang_tree = pcall(ts.get_parser, self.bufnr, self.filetype)
  if not ok or not lang_tree then
    return match, ranges, line
  end
  ---@type integer
  local ptn
  lang_tree:for_each_tree(function(tstree, ltree)
    local tsroot = tstree:root()
    local root_start_row, _, root_end_row, _ = tsroot:range()
    if (root_start_row > self.cur_row) or (root_end_row < self.cur_row) then
      return
    end
    local lang = ltree:lang()
    local queries = tsq.get(lang, 'highlights')
    if not queries then
      return
    end
    local iter = queries:iter_matches(tsroot, self.bufnr, self.cur_row, self.cur_row + 1, { all = true })
    for pattern, matches in iter do
      for int, nodes in pairs(matches) do
        local capture = queries.captures[int]
        if vim.tbl_contains(self.opt.captures, capture) then
          for _, node in ipairs(nodes) do
            local tsrange = { node:range() }
            ranges[pattern] = util.tbl_insert(ranges, pattern, tsrange)
            if tsrange[1] == self.cur_row then
              table.insert(line, tsrange)
              if (tsrange[2] <= self.cur_col) and (tsrange[4] > self.cur_col) then
                local parent = node:parent()
                if parent then
                  match = { node = parent, range = tsrange }
                  ptn = pattern
                end
              end
            end
          end
        end
      end
    end
  end)
  return match, ranges[ptn] or {}, line
end

-- Whether the cursor position is at the node starting point
---@param cur_row integer
---@param current Range4
---@param parent Range4
---@return boolean is_start
local function _is_start_point(cur_row, current, parent)
  if cur_row == parent[3] then
    if current[4] == parent[4] then
      return true
    end
    if parent[1] ~= parent[3] then
      return current[2] == parent[2]
    end
  end
  return false
end

-- Whether the pair's position is on-screen or off-screen
function matchwith.pair_marker_state(self, is_start, pair)
  local pair_row, pair_scol, pair_ecol = unpack(pair)
  local leftcol = fn.winsaveview().leftcol
  local wincol = fn.wincol()
  local win_width = api.nvim_win_get_width(self.winid)
  if api.nvim_get_option_value('list', { win = self.winid }) then
    local listchars = vim.opt.listchars:get()
    local precedes = listchars.precedes and 1 or 0
    local extends = listchars.extends and 1 or 0
    win_width = win_width - extends
    leftcol = leftcol + precedes
  end
  local num = 0
  if pair_scol > self.cur_col then
    if pair_scol > (self.cur_col + (win_width - wincol)) then
      num = 3
    end
  elseif pair_ecol < leftcol then
    num = 6
  end
  local is_over = (num > 0) and (self.cur_row ~= pair_row)
  if is_start then
    if is_over or (pair_row < self.top_row) then
      num = num + 1
    end
  elseif is_over or (pair_row > self.bottom_row) then
    num = num + 2
  end
  local resp = (num > 0) and { HL_OFF_SCREEN, DIR_SIGN[num] } or { HL_ON_SCREEN }
  return resp[1], resp[2]
end

-- Detect matchpair range
---@param is_forward boolean
---@param node TSNode?
---@param ranges Range4[]
---@param count integer
---@return Range4|vim.NIL
local function _find_sibling(is_forward, node, ranges, count)
  for _ = 1, count, 1 do
    for _, range in ipairs(ranges) do
      if not node then
        return vim.NIL
      end
      if vim.deep_equal(range, { node:range() }) then
        return range
      end
    end
    node = is_forward and node:next_sibling() or node:prev_sibling()
  end
  return vim.NIL
end

-- Get hlgroup and pair range
function matchwith.get_matchpair(self, match, ranges)
  local node = match.node
  local node_range = { node:range() }
  local is_start = _is_start_point(self.cur_row, match.range, node_range)
  -- Query.iter_matches may not be able to get the bracket range, so we need to add it
  if node_range[1] ~= node_range[3] then
    local pairspec = is_start and { node_range[1], node_range[2], node_range[1], node_range[2] + 1 }
      or { node_range[3], node_range[4] - 1, node_range[3], node_range[4] }
    table.insert(ranges, pairspec)
  end
  local count = node:child_count() - 1
  local pair_range = is_start and _find_sibling(true, node:child(0), ranges, count)
    or _find_sibling(false, node:child(count), ranges, count)
  local marker_range = { node_range[1], node_range[3] + 1 }
  return is_start, pair_range, marker_range
end

function matchwith.draw_markers(self, is_start, match, pair)
  local word_range = _convert_range(match)
  local pair_range = _convert_range(pair)
  local is_insert = util.is_insert_mode(self.mode)
  local hlgroup, symbol = self:pair_marker_state(is_start, pair_range)
  self:add_marker(hlgroup, word_range)
  self:add_marker(hlgroup, pair_range)
  if not is_insert and (fn.foldclosed(self.cur_row + 1) == -1) then
    if hlgroup == HL_OFF_SCREEN then
      self:set_indicator(symbol)
    end
  end
  return { match, pair }
end

function matchwith.add_marker(self, hlgroup, word_range)
  api.nvim_buf_add_highlight(self.bufnr, self.ns, hlgroup, unpack(word_range))
end

function matchwith.set_indicator(self, symbol)
  if (self.opt.indicator > 0) and symbol then
    util.indicator(symbol, self.opt.indicator, self.cur_row, self.cur_col)
  end
end

-- Update matched pairs
function matchwith.matching(row, col)
  if vim.g.matchwith_disable or vim.b.matchwith_disable then
    return
  end
  if cache.skip_matching then
    cache.skip_matching = false
    return
  end

  local session = matchwith.new(row, col)
  if session.filetype == '' or vim.tbl_contains(session.opt.ignore_filetypes, session.filetype) then
    return
  end
  if (session.cur_row == cache.last.row) and (session.changetick == cache.changetick) then
    if
      not vim.tbl_isempty(cache.last.state)
      and (cache.last.state[1][2] <= session.cur_col)
      and (cache.last.state[1][4] > session.cur_col)
    then
      return
    end
    cache.last.state = {}
  else
    cache.changetick = session.changetick
  end
  local clear_marker = session:clear_ns()
  if clear_marker then
    cache.marker_range = {}
  end
  local match, ranges, line = session:get_matches()
  cache.last.line = line
  if not match then
    cache.last.row = session.cur_row
    cache.last.state = {}
    return
  end
  if vim.tbl_isempty(ranges) then
    cache.last = { row = session.cur_row, state = {}, ranges = {} }
    return
  end
  local is_start, pair_range, marker_range = session:get_matchpair(match, ranges)
  if pair_range ~= vim.NIL then
    ---@cast pair_range -vim.NIL
    cache.marker_range = marker_range
    cache.last.row = session.cur_row
    if row and col then
      cache.last.state = { match.range, pair_range }
    else
      cache.last.state = session:draw_markers(is_start, match.range, pair_range)
    end
  end
end

function matchwith.jumping()
  local vcount = vim.v.count1
  if vcount > 1 then
    vim.cmd(string.format('normal! %s%%', vcount))
    return
  end
  if vim.tbl_isempty(cache.last.state) then
    if vim.tbl_isempty(cache.last.line) then
      vim.cmd('normal! %')
      return
    end
    local pos = api.nvim_win_get_cursor(0)
    for _, range in ipairs(cache.last.line) do
      if (range[1] + 1) == pos[1] and (range[2] > pos[2]) then
        matchwith.matching(range[1], range[2])
        break
      end
    end
  end
  cache.skip_matching = true
  local row, scol = unpack(cache.last.state[2])
  api.nvim_win_set_cursor(0, { row + 1, scol })
  local session = matchwith.new(row, scol)
  local is_start = cache.last.state[1][1] >= cache.last.state[2][1]
  session:clear_ns()
  session:draw_markers(is_start, cache.last.state[2], cache.last.state[1])
  cache.last.state = { [1] = cache.last.state[2], [2] = cache.last.state[1] }
end

-- Configure Matchwith settings
function matchwith.setup(opts)
  require('matchwith.config').set_options(opts)
end

---TODO: later
---Get and set user-defined matchpairs
-- matchwith.set_matchpairs = function(self)
--   self.matchpairs = vim.tbl_map(function(v)
--     -- if not v:find('[([{]') then
--     return vim.split(v, ':', { plain = true })
--   end, vim.split(vim.bo[self.bufnr].matchpairs, ',', { plain = true }))
-- end

util.autocmd('BufEnter', {
  desc = 'Matchwith ignore buftypes',
  group = matchwith.augroup,
  callback = function()
    if vim.b.matchwith_disable or vim.bo.buftype == '' then
      return
    end
    local ignore_items = matchwith.opt.ignore_buftypes
    vim.b.matchwith_disable = vim.tbl_contains(ignore_items, vim.bo.buftype)
  end,
})

util.autocmd({ 'CursorMoved', 'CursorMovedI' }, {
  desc = 'Update matchpair highlight',
  group = matchwith.augroup,
  callback = function()
    matchwith.timer.debounce(matchwith.opt.debounce_time, function()
      matchwith.matching()
    end)
  end,
})

util.autocmd({ 'InsertEnter', 'InsertLeave' }, {
  desc = 'Update matchpair highlight',
  group = matchwith.augroup,
  callback = function()
    matchwith.matching()
  end,
})

util.autocmd({ 'ColorScheme' }, {
  desc = 'Reload matchwith hlgroups',
  group = matchwith.augroup,
  callback = function()
    util.set_hl(matchwith.opt.highlights)
  end,
}, true)

return matchwith
