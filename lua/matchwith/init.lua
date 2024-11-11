---@module 'util'
local util = setmetatable({}, {
  __index = function(t, k)
    t = package.loaded['fret.util'] or require('matchwith.util')
    return t[k]
  end,
})
local api = vim.api
local fn = vim.fn
local ts = vim.treesitter
local tsq = ts.query

local UNIQ_ID = 'Matchwith-nvim'
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
matchwith.hlgroups = _G.Matchwith_hlgroup
_G.Matchwith_hlgroup = nil

-- util module hub
function matchwith.util_call()
  return util
end

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
  self['opt'] = {
    ignore_filetypes = vim.g.matchwith_ignore_filetypes,
    captures = vim.g.matchwith_captures,
    indicator = vim.g.matchwith_indicator,
    sign = vim.g.matchwith_sign,
    symbols = vim.g.matchwith_symbols,
  }
  return self
end

-- Clear highlights for a matchpair
function matchwith.clear_ns(self)
  local clear = false
  if not vim.tbl_isempty(cache.marker_range) then
    -- api.nvim_buf_clear_namespace(0, self.ns, cache.marker_range[1], cache.marker_range[2])
    api.nvim_buf_clear_namespace(0, self.ns, 0, -1)
    clear = true
  end
  return clear
end

---Get match items
function matchwith.get_matches(self)
  ---@type MatchItem?, Range4[], Range4[]
  local match, ranges, line = nil, {}, {}
  -- TODO: Should handle get_parser return value change in neovim 12.
  ---@type boolean, vim.treesitter.LanguageTree?
  local ok, lang_tree
  if ts._get_parser then
    lang_tree = ts._get_parser(self.bufnr, self.filetype)
    if not lang_tree then
      return match, ranges, line
    end
  else
    ok, lang_tree = pcall(ts.get_parser, self.bufnr, self.filetype)
    if not ok or not lang_tree then
      return match, ranges, line
    end
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
    if not queries or lang == 'markdown' then
      return
    end
    local iter = queries:iter_matches(tsroot, self.bufnr, self.cur_row, self.cur_row + 1, { all = true })
    for pattern, matches in iter do
      for int, nodes in pairs(matches) do
        local capture = queries.captures[int]
        if vim.tbl_contains(self.opt.captures, capture) then
          for _, node in ipairs(nodes) do
            local tsrange = { node:range() }
            util.tbl_insert(ranges, pattern, tsrange)
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
    local extends, precedes = util.expand_wrap_symbols()
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
  local resp = (num > 0) and { self.hlgroups.off, self.opt.symbols[num] } or { self.hlgroups.on }
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

---Set user-defined matchpairs
function matchwith.set_userdef()
  local chars, matchpair = {}, {}
  vim.tbl_map(function(v)
    ---@type string,string
    local s, e = unpack(vim.split(v, ':', { plain = true }))
    local s_ = s == '[' and '\\[' or s
    local e_ = e == ']' and '\\]' or e
    matchpair[s] = { s_, '', e_, 'nW' }
    matchpair[e] = { s_, '', e_, 'bnW' }
    vim.list_extend(chars, { e, s })
  end, vim.split(vim.bo.matchpairs, ',', { plain = true }))
  cache.userdef = { chars = chars, matchpair = matchpair }
end

function matchwith.clear_userdef()
  cache.userdef = nil
end

---Check user-defined matchpairs
function matchwith.user_matchpair(self, match, line)
  local state = {}
  if not match then
    local line_str = vim.api.nvim_get_current_line()
    local search_opts
    if vim.fn.type(line_str) ~= 10 then
      local charidx = vim.str_utfindex(line_str, self.cur_col)
      local char = vim.fn.strcharpart(line_str, charidx, 1)
      search_opts = cache.userdef.matchpair[char]
    end
    if search_opts then
      local pos = fn.searchpairpos(unpack(search_opts))
      if (pos[1] + pos[2]) ~= 0 then
        local row, col = util.zerobase(pos[1]), util.zerobase(pos[2])
        match = {
          range = { self.cur_row, self.cur_col, self.cur_row, self.cur_col + 1 },
          is_start = search_opts[4] == 'nW',
        }
        local pair = { row, col, row, col + 1 }
        state = { match.range, pair }
      end
    else
      local s = self.cur_col + 2
      local e = line[1] and (line[1][4] - 1) or #line_str
      if (e - s) > 0 then
        line_str = line_str:sub(s, e)
        local iter = vim.iter(cache.userdef.chars)
        if iter:find(function(v)
          return line_str:find(v, 1, true)
        end) then
          line = {}
        end
      end
    end
  end
  return match, { row = self.cur_row, state = state, line = line }
end

function matchwith.draw_markers(self, is_start, match, pair)
  local word_range = _convert_range(match)
  local pair_range = _convert_range(pair)
  local is_insert = util.is_insert_mode(self.mode)
  local hlgroup, symbol = self:pair_marker_state(is_start, pair_range)
  self:add_marker(hlgroup, word_range)
  self:add_marker(hlgroup, pair_range)
  if not is_insert and (fn.foldclosed(self.cur_row + 1) == -1) then
    if hlgroup == self.hlgroups.off then
      self:set_indicator(symbol)
    end
  end
  return { match, pair }
end

function matchwith.add_marker(self, hlgroup, word_range)
  api.nvim_buf_add_highlight(self.bufnr, self.ns, hlgroup, unpack(word_range))
end

function matchwith.set_indicator(self, symbol)
  if symbol then
    if self.opt.sign then
      local opts = { sign_hl_group = matchwith.hlgroups.sign, sign_text = symbol, priority = 0 }
      util.ext_sign(self.ns, self.cur_row, self.cur_col, opts)
    end
    if self.opt.indicator > 0 then
      util.indicator(self.ns, symbol, self.opt.indicator, self.cur_row, self.cur_col)
    end
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
  if vim.tbl_contains(session.opt.ignore_filetypes, session.filetype) then
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
  else
    cache.changetick = session.changetick
  end
  local clear_marker = session:clear_ns()
  if clear_marker then
    cache.marker_range = {}
  end
  if not cache.userdef then
    matchwith.set_userdef()
  end
  local match, ranges, line = session:get_matches()
  match, cache.last = session:user_matchpair(match, line)
  if not match then
    return
  end
  if match.is_start ~= nil then
    cache.marker_range = { session.cur_row, cache.last.state[2][1] + 1 }
    session:draw_markers(match.is_start, unpack(cache.last.state))
    return
  end
  --TODO: errors for "else" must be addressed
  -- if #ranges < 2 then
  --   return
  -- end

  local is_start, pair_range, marker_range = session:get_matchpair(match, ranges)
  if pair_range ~= vim.NIL then
    ---@cast pair_range -vim.NIL
    cache.marker_range = marker_range
    if row and col then
      cache.last.state = { match.range, pair_range }
    else
      cache.last.state = session:draw_markers(is_start, match.range, pair_range)
    end
  else
    cache.last.state = {}
  end
  return true
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
    ---@type boolean?
    local ok
    for _, range in ipairs(cache.last.line) do
      if (range[1] + 1) == pos[1] and (range[2] > pos[2]) then
        ok = matchwith.matching(range[1], range[2])
        break
      end
    end
    if not ok then
      return
    end
  end
  ---TODO:Need to fix a bug that is causing the switch_statement to not correctly get the range it returns.
  if vim.tbl_isempty(cache.last.state) then
    return
  end
  cache.skip_matching = true
  local row, scol = unpack(cache.last.state[2])
  api.nvim_win_set_cursor(0, { row + 1, scol })
  local session = matchwith.new(row, scol)
  local is_start = cache.last.state[1][1] < cache.last.state[2][1]
  session:clear_ns()
  session:draw_markers(is_start, cache.last.state[2], cache.last.state[1])
  cache.last.state = { [1] = cache.last.state[2], [2] = cache.last.state[1] }
end

-- Configure Matchwith settings
function matchwith.setup(opts)
  local ok = require('matchwith.config').set_options(opts)
  if not ok then
    util.notify(UNIQ_ID, 'Error: Requires arguments', vim.log.levels.ERROR)
  end
end

return matchwith
