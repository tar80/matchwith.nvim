local api = vim.api
local ts = vim.treesitter
local tsq = ts.query
local util = require('matchwith.util')

local UNIQ_ID = 'Matchwith'
local DEFALUT_OPTIONS = {
  debounce_time = 80,
  ignore_filetypes = { 'vimdoc' },
  ignore_buftypes = { 'nofile' },
  captures = { 'keyword.function', 'keyword.repeat', 'keyword.conditional', 'punctuation.bracket' },
}
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
matchwith.augroup = vim.api.nvim_create_augroup(UNIQ_ID, {})
matchwith.opt = vim.tbl_extend('keep', DEFALUT_OPTIONS, _G.Matchwith_prepare)
_G.Matchwith_prepare = nil

-- Adjust column if mode is insert-mode
local function _adjust_col(mode, col)
  local dec = util.is_insert_mode(mode) and 1 or 0
  return math.max(0, col - dec)
end

-- Convert range from Range4 to WordRange(row,scol,ecol)
---@package
---@param node TSNode|Range4
---@return WordRange
local function _convert_range(node)
  local start_row, start_col, _, end_col = ts.get_node_range(node)
  return { start_row, start_col, end_col }
end

-- Start a new instance
function matchwith.new(row, col)
  local pos = api.nvim_win_get_cursor(0)
  local self = setmetatable({}, { __index = matchwith })
  self.mode = api.nvim_get_mode().mode
  self.bufnr = api.nvim_get_current_buf()
  self.filetype = api.nvim_get_option_value('filetype', { buf = self.bufnr })
  -- adjust row to zero-base
  self.top_row = util.zerobase(vim.fn.line('w0'))
  self.bottom_row = util.zerobase(vim.fn.line('w$'))
  self.cur_row = row or util.zerobase(pos[1])
  self.cur_col = col or _adjust_col(self.mode, pos[2])
  self.changetick = vim.b[self.bufnr].changedtick
  return self
end

-- Clear highlights for a matchpair
function matchwith.clear_ns(self)
  if not vim.tbl_isempty(cache.marker_range) then
    api.nvim_buf_clear_namespace(0, self.ns, cache.marker_range[1], cache.marker_range[2])
    return true
  end
  return false
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
    if root_start_row > self.cur_row or root_end_row < self.cur_row then
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
local function _is_start_node(cur_row, current, parent)
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

-- Detect matchpair range
---@param next boolean
---@param node TSNode?
---@param ranges Range4[]
---@param count integer
---@return Range4|vim.NIL
local function _find_sibling(next, node, ranges, count)
  for _ = 1, count, 1 do
    for _, range in ipairs(ranges) do
      if not node then
        return vim.NIL
      end
      if vim.deep_equal(range, { node:range() }) then
        return range
      end
    end
    node = next and node:next_sibling() or node:prev_sibling()
  end
  return vim.NIL
end

-- Get hlgroup and pair range
function matchwith.get_matchpair(self, match, ranges)
  local node = match.node
  local node_range = { node:range() }
  local is_start = _is_start_node(self.cur_row, match.range, node_range)
  -- Query.iter_matches may not be able to get the bracket range, so we need to add it
  if node_range[1] ~= node_range[3] then
    local pairspec = is_start and { node_range[1], node_range[2], node_range[1], node_range[2] + 1 }
      or { node_range[3], node_range[4] - 1, node_range[3], node_range[4] }
    table.insert(ranges, pairspec)
  end
  ---@type Range4|vim.NIL
  local pair_range = vim.NIL
  local hlgroup = HL_ON_SCREEN
  local count = node:child_count() - 1
  if is_start then
    if node_range[1] < self.top_row then
      hlgroup = HL_OFF_SCREEN
    end
    pair_range = _find_sibling(true, node:child(0), ranges, count)
  else
    if node_range[3] > self.bottom_row then
      hlgroup = HL_OFF_SCREEN
    end
    pair_range = _find_sibling(false, node:child(count), ranges, count)
  end
  local marker_range = { node_range[1], node_range[3] + 1 }
  return hlgroup, pair_range, marker_range
end

function matchwith.draw_markers(self, hlgroup, match, pair)
  self:marker(hlgroup, _convert_range(match))
  self:marker(hlgroup, _convert_range(pair))
  return { match, pair }
end

function matchwith.marker(self, hlgroup, word_range)
  api.nvim_buf_add_highlight(self.bufnr, self.ns, hlgroup, unpack(word_range))
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
  local hlgroup, pair_range, marker_range = session:get_matchpair(match, ranges)
  if pair_range ~= vim.NIL then
    ---@cast pair_range -vim.NIL
    cache.marker_range = marker_range
    cache.last.row = session.cur_row
    cache.last.state = session:draw_markers(hlgroup, match.range, pair_range)
  end
end

function matchwith.update_markers(self)
  local cur_row = util.zerobase(api.nvim_win_get_cursor(0)[1])
  local start_row, end_row = cache.last.state[1][1], cache.last.state[2][1]
  local in_screen
  if cur_row >= start_row then
    in_screen = vim.fn.line('w0') <= start_row
  else
    in_screen = vim.fn.line('w$') > end_row
  end
  local hlgroup = in_screen and HL_ON_SCREEN or HL_OFF_SCREEN
  self.bufnr = 0
  self:clear_ns()
  self:draw_markers(hlgroup, cache.last.state[1], cache.last.state[2])
end

function matchwith.jumping(self)
  local vcount = vim.v.count1
  if vcount > 1 then
    vim.cmd(string.format('normal! %s%%', vcount))
    return
  end
  local skip = false
  if vim.tbl_isempty(cache.last.state) then
    if vim.tbl_isempty(cache.last.line) then
      vim.cmd('normal! %')
      return
    end
    local pos = api.nvim_win_get_cursor(0)
    for _, range in ipairs(cache.last.line) do
      if (range[1] + 1) == pos[1] and (range[2] > pos[2]) then
        self.matching(range[1], range[2])
        skip = true
        break
      end
    end
  end
  cache.skip_matching = true
  local row, scol = unpack(cache.last.state[2])
  api.nvim_win_set_cursor(0, { row + 1, scol })
  if not skip then
    self:update_markers()
  end
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

local timer = util.debounce(matchwith.opt.debounce_time, function()
  require('matchwith').matching()
end)

util.autocmd({ 'CursorMoved', 'CursorMovedI' }, {
  group = matchwith.augroup,
  desc = 'Update matchpair highlight',
  callback = function()
    timer:start()
  end,
})

util.autocmd({ 'InsertEnter', 'InsertLeave' }, {
  group = matchwith.augroup,
  desc = 'Update matchpair highlight',
  callback = function()
    require('matchwith').matching()
  end,
})

return matchwith
