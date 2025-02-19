---@class Matchwith
local matchwith = {}

local util = require('matchwith.util')
local ts = require('matchwith.treesitter')
local api = vim.api
local fn = vim.fn
local timer = util.set_timer()

--[[ NOTE:
-- The cursor position is calculated based on a zero index.
-- Additionally, as of version v0.11.0-dev-1216, the fourth value of Range4 needs to be decremented by 1.
-- (which means that adjustments to the end of the word are necessary)
--]]
local zerobase = util.zerobase

local UNIQUE_ID = 'Matchwith-nvim'
local _cache = {
  changetick = 0,
  last = { word = {}, current = {}, parent = {} },
  markers = {},
  skip_matching = false,
}
---@class Cache
local cache = vim.deepcopy(_cache)
cache.ns = api.nvim_create_namespace(UNIQUE_ID)

function matchwith.clear_ns(self, marker)
  local clear = false
  if self.cur_row ~= cache.last.word[1] or (self.cur_col < cache.last.word[2] or cache.last.word[3] < self.cur_col) then
    api.nvim_buf_clear_namespace(self.bufnr, cache.ns, marker[1], marker[2])
    clear = true
  end
  return clear
end

-- Adjust column for insert-mode
---@package
---@param mode string
---@param col integer
---@return integer column
local function _adjust_column(mode, col)
  local dec = util.is_insert_mode(mode) and 1 or 0
  return math.max(0, col - dec)
end

function matchwith.new(row, col)
  local self = setmetatable({}, { __index = matchwith })
  local pos = api.nvim_win_get_cursor(0)
  self['opt'] = {
    ignore_filetypes = vim.g.matchwith_ignore_filetypes,
    depth_limit = vim.g.matchwith_depth_limit,
    captures = vim.g.matchwith_captures,
    indicator = vim.g.matchwith_indicator,
    sign = vim.g.matchwith_sign,
    symbols = vim.g.matchwith_symbols,
    show_parent = vim.g.matchwith_show_parent,
    show_next = vim.g.matchwith_show_next,
  }
  self['mode'] = api.nvim_get_mode().mode
  self['bufnr'] = api.nvim_get_current_buf()
  self['winid'] = api.nvim_get_current_win()
  self['filetype'] = api.nvim_get_option_value('filetype', { buf = self.bufnr })
  self['changetick'] = api.nvim_buf_get_changedtick(self.bufnr)
  self['top_row'] = zerobase(fn.line('w0'))
  self['bottom_row'] = zerobase(fn.line('w$'))
  self['cur_row'] = row or zerobase(pos[1])
  self['cur_col'] = col or _adjust_column(self.mode, pos[2])
  self['sentence'] = vim.api.nvim_get_current_line()
  self['match'] = {}
  self['next_match'] = nil
  self['node_ranges'] = {}
  self['markers'] = {}
  self['last'] = vim.deepcopy(_cache.last)
  return self
end

---@param instance Matchwith
---@param tsroot TSNode
---@param queries vim.treesitter.Query
---@return MatchItem,TSNode[],table<integer,Range4>
local function iterate_langtree(instance, tsroot, queries)
  ---@type MatchItem, TSNode, table<integer,Range4>
  local match, next_match, classes = {}, nil, {}

  local iter = queries:iter_matches(tsroot, instance.bufnr, instance.cur_row, instance.cur_row + 1, { all = true })
  for _, matches in iter do
    for id, nodes in pairs(matches) do
      local capture = queries.captures[id]
      if vim.tbl_contains(instance.opt.captures, capture) then
        for _, node in ipairs(nodes) do
          local tsrange = ts.range4(node)
          if tsrange[1] < instance.cur_row then
            table.insert(classes, tsrange)
            match = { node = node, range = tsrange, at_cursor = false }
          elseif tsrange[1] == instance.cur_row then
            if tsrange[2] <= instance.cur_col then
              table.insert(classes, tsrange)
              match = { node = node, range = tsrange }
              if tsrange[3] == instance.cur_row and zerobase(tsrange[4]) >= instance.cur_col then
                match.at_cursor = true
              end
            else
              if not next_match and not match.at_cursor then
                next_match = node
              end
              break
            end
          else
            break
          end
        end
      end
    end
  end
  return match, next_match, classes or {}
end

function matchwith.get_matches(self)
  ---@type MatchItem, TSNode, Range4[]
  local match, next_match, node_ranges = {}, nil, {}

  ---@type vim.treesitter.LanguageTree?
  local parsers = ts.get_parsers(self)
  if parsers then
    parsers:for_each_tree(function(tstree, langtree)
      local language = langtree:lang()
      if language == 'markdown' then
        return
      end
      local tsroot = tstree:root()
      local root_range = ts.range4(tsroot)
      if root_range[1] <= self.cur_row and self.cur_row <= root_range[3] then
        local queries = ts.get_query(language)
        if queries then
          match, next_match, node_ranges = iterate_langtree(self, tsroot, queries)
          if not vim.tbl_isempty(match) or next_match then
            self.match, self.next_match, self.node_ranges = match, next_match, node_ranges or {}
          end
        end
      end
    end)
  end
end

-- Get parenthesis from matchpairs
---@param char string A bracket character
---@return string[] parenthesis, IsStartPoint direction
local function _get_parenthesis(char)
  local parenthesis = {}
  local is_start_point
  if char then
    local matchpair = cache.searchpairs.matchpair[char]
    if matchpair then
      parenthesis = { matchpair[1]:sub(-1), matchpair[3]:sub(-1) }
      is_start_point = matchpair[4] == 'nW'
    end
  end
  return parenthesis, is_start_point
end

-- Find the bracket's node within the scope
---@param parent TSNode
---@param bracket string|nil A character when target node type is bracket
---@return Range4|nil
local function _find_bracket_range(parent, bracket)
  local range
  for child in parent:iter_children() do
    if child:type() == bracket then
      range = ts.range4(child)
      break
    end
  end
  return range
end

-- Find range4 as the starting point from the parent node
---@package
---@param parent TSNode
---@param node_ranges Range4[]
---@param count integer
---@param bracket? string
---@return Range4|nil
local function find_start_range(parent, node_ranges, count, bracket)
  local range
  if bracket then
    range = _find_bracket_range(parent, bracket)
  else
    local node = parent:child(0)
    local first_child_range = node and ts.range4(node)
    for _ = 1, count, 1 do
      for _, child_range in ipairs(node_ranges) do
        if not node then
          return first_child_range
        end
        if vim.deep_equal(child_range, ts.range4(node)) then
          return child_range
        end
      end
      node = node:next_sibling()
    end
    range = first_child_range
  end
  return range
end

-- Find range4 as the end point from the parent node
---@package
---@param parent TSNode Class root node
---@param count integer Child node count
---@param bracket? string A character when target node type is bracket
---@return Range4|nil range Class end point node range
local function find_end_range(parent, count, bracket)
  local range
  if bracket then
    range = _find_bracket_range(parent, bracket)
  elseif parent:type():find('else', 1, true) then
    local _parent = parent:parent()
    if _parent then
      count = ts.child_count(_parent)
      range = ts.range4(_parent:child(count) --[[@as TSNode]])
    end
  else
    range = ts.range4(parent:child(count) --[[@as TSNode]])
  end
  return range
end

---@param line_str string Text of current line
---@param col integer Cursor column
---@return string[]|nil
local function _get_searchpair_options(line_str, col)
  if vim.fn.type(line_str) ~= 10 then
    local charidx = vim.str_utfindex(line_str, col)
    local char = vim.fn.strcharpart(line_str, charidx, 1)
    return cache.searchpairs.matchpair[char]
  end
end

function matchwith.verify_searchpairpos(self)
  local searchpair_opts = _get_searchpair_options(self.sentence, self.cur_col)
  if searchpair_opts then
    local pair_pos = fn.searchpairpos(unpack(searchpair_opts))
    if (pair_pos[1] + pair_pos[2]) ~= 0 then
      local pair_row, pair_col = zerobase(pair_pos[1]), zerobase(pair_pos[2])
      local pair_range = { pair_row, pair_col, pair_row, pair_col + 1 }
      self.match = {
        range = { self.cur_row, self.cur_col, self.cur_row, self.cur_col + 1 },
        is_start_point = searchpair_opts[4] == 'nW',
        at_cursor = true,
      }
      self.last.current = { self.match.range, pair_range }
    end
  end
end

function matchwith.verify_next_match(self)
  --[[ NOTE:
  --  This checks whether the match target of matchpairs includes the range from just after the cursor position
  --  to just before the match. Therefore, the starting point is +1 and the ending point is -1.
  --  Additionally, since the starting point is zero-based, it needs to be incremented by +2.
  --]]
  local has_next_match = type(self.next_match) == 'userdata'
  local next_range = has_next_match and ts.range4(self.next_match)
  local scol = self.cur_col + 2
  local ecol = next_range and next_range[4] - 1 or #self.sentence
  if (ecol - scol) > 0 then
    local sentence = self.sentence:sub(scol, ecol)
    local searchpair = vim.iter(cache.searchpairs.chars):find(function(v)
      return sentence:find(v, 1, true)
    end)
    if searchpair then
      -- vim.notify('@@@matchpairs! ' .. searchpair .. ', row:' .. self.cur_row .. ', col:' .. self.cur_col, 3)
      self.match.is_comment = not has_next_match
      cache.last.word = { self.cur_row, scol, ecol }
      cache.last.current = {}
      return
    end
  end
  if next_range then
    local parent = self.next_match:parent()
    if parent then
      local parenthesis, is_start_point = _get_parenthesis(self.next_match:type())
      local count = ts.child_count(parent)
      table.insert(self.node_ranges, next_range)
      local start_range = find_start_range(parent, self.node_ranges, count, parenthesis[1])
      if start_range then
        local end_range = find_end_range(parent, count, parenthesis[2])
        if end_range then
          self.last.current = is_start_point and { start_range, end_range } or { end_range, start_range }
          self.last.word = { self.cur_row, self.cur_col, zerobase(start_range[2]) }
          if not self.match.node then
            self.match =
              { node = self.next_match, range = next_range, at_cursor = false, is_start_point = is_start_point }
          end
        end
      end
    end
  end
end

-- Get the ancestor of the current node
---@parem node TSNode
---@param node_ranges Range4[]
---@param depth_limit integer
---@return TSNode?
local function _get_ancestor(node, node_ranges, depth_limit)
  local l = depth_limit
  while l ~= 0 do
    l = l - 1
    node = node:parent()
    if not node then
      break
    end
    local child = ts.range4(node:child(0))
    for _, ancestor in ipairs(node_ranges) do
      if ancestor[1] == child[1] and ancestor[2] == child[2] and ancestor[4] == child[4] then
        return node
      end
    end
  end
end

function matchwith.get_matchpair(self)
  local parent = self.match.node:parent()
  if parent then
    local count = ts.child_count(parent)
    local start_range = find_start_range(parent, self.node_ranges, count)
    if start_range then
      local parenthesis = _get_parenthesis(self.match.node:type())
      local end_range = find_end_range(parent, count, parenthesis[2])
      if not end_range then
        -- NOTE: for test!
        vim.notify('end_range could not get', 4)
        return
      end
      if (end_range[3] == self.cur_row) and (zerobase(end_range[4]) < self.cur_col) then
        parent = _get_ancestor(parent, self.node_ranges, self.opt.depth_limit)
        if not parent then
          return
        end
        count = ts.child_count(parent)
        start_range = ts.range4(parent:child(0) --[[@as TSNode]])
        end_range = ts.range4(parent:child(count) --[[@as TSNode]])
      end
      if vim.tbl_isempty(self.last.current) and not self.match.is_comment then
        self.match.is_start_point = self.match.at_cursor and vim.deep_equal(self.match.range, start_range)
        self.last.current = self.match.is_start_point and { start_range, end_range } or { end_range, start_range }
        self.last.word = { self.cur_row, self.last.current[1][2], zerobase(self.last.current[1][4]) }
      end
      self.last.parent = { start_range, end_range }
      if start_range[1] == end_range[3] then
        self.last.word = { self.cur_row, start_range[2], zerobase(end_range[4]) }
      end
    end
  end
end

-- Get the screen offset value and define the pair_marker_state method
---@param winid integer
local function _get_screen_offset(winid)
  local leftcol = fn.winsaveview().leftcol
  local wincol = fn.wincol()
  local win_width = api.nvim_win_get_width(winid)
  if api.nvim_get_option_value('list', { win = winid }) then
    local extends, precedes = util.expand_listchars()
    win_width = win_width - extends
    leftcol = leftcol + precedes
  end

  -- Whether the pair's position is on-screen or off-screen
  function matchwith.pair_marker_state(self, pair_range)
    local pair_row, pair_scol, pair_ecol = unpack(pair_range)
    local num = 0
    if pair_scol > self.cur_col then
      if pair_scol > (self.cur_col + (win_width - wincol)) then
        num = 3
      end
    elseif pair_ecol < leftcol then
      num = 6
    end
    local is_over = (num > 0) and (self.cur_row ~= pair_row)
    if self.match.is_start_point then
      if is_over or (pair_row < self.top_row) then
        num = num + 1
      end
    elseif is_over or (pair_row > self.bottom_row) then
      num = num + 2
    end
    return num
  end
end

function matchwith.draw_markers(self)
  _get_screen_offset(self.winid)
  local last = cache.last
  if not vim.tbl_isempty(last.current) then
    -- if self.match.is_current or self.opt.show_next then
    local word_range = ts.convert_wordrange(last.current[1])
    local pair_range = ts.convert_wordrange(last.current[2])
    local num = self:pair_marker_state(pair_range)
    local hl = num == 0 and cache.hlgroups.ON or cache.hlgroups.OFF
    self:add_marker(hl, word_range)
    self:add_marker(hl, pair_range)
    local is_insert = util.is_insert_mode(self.mode)
    if not is_insert and (fn.foldclosed(self.cur_row + 1) == -1) then
      if num > 0 then
        self:set_indicator(self.opt.symbols[num])
      end
    end
    -- end
  end
  if not vim.tbl_isempty(last.parent) then
    local word_range = ts.convert_wordrange(last.parent[1])
    local pair_range = ts.convert_wordrange(last.parent[2])
    local num = self:pair_marker_state(pair_range)
    local hl = num == 0 and cache.hlgroups.PARENT_ON or cache.hlgroups.PARENT_OFF
    self:add_marker(hl, word_range)
    self:add_marker(hl, pair_range)
  end
end

function matchwith.add_marker(self, hlgroup, word_range)
  api.nvim_buf_add_highlight(self.bufnr, cache.ns, hlgroup, unpack(word_range))
end

function matchwith.set_searchpairs()
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
  cache.searchpairs = { chars = chars, matchpair = matchpair }
end

function matchwith.set_indicator(self, symbol)
  if symbol then
    if self.opt.sign then
      local opts = { sign_hl_group = cache.hlgroups.SIGN, sign_text = symbol, priority = 0 }
      util.ext_sign(cache.ns, self.cur_row, self.cur_col, opts)
    end
    if self.opt.indicator > 0 then
      util.indicator(cache.ns, symbol, self.opt.indicator, self.cur_row, self.cur_col)
    end
  end
end

-- Determines whether to update match information or use cache
---@package
---@param col integer Current cursor column
---@param range WordRange
---@return boolean?
local function _is_cache_valid(col, range)
  if not vim.tbl_isempty(cache.last.word) then
    return (range[2] <= col and col < range[3])
  end
end

local function set_markers(is_start_point, last, markers)
  if not vim.tbl_isempty(last.current) then
    markers.current = is_start_point and { last.current[1][1], last.current[2][3] + 1 }
      or { last.current[2][1], last.current[1][3] + 1 }
  end
  if not vim.tbl_isempty(last.parent) then
    markers.parent = { last.parent[1][1], last.parent[2][3] + 1 }
  end
end

function matchwith.matching(row, col)
  if cache.skip_matching then
    cache.skip_matching = false
    return
  end

  local session = matchwith.new(row, col)
  if (session.cur_row == cache.last.word[1]) and (session.changetick == cache.changetick) then
    if _is_cache_valid(session.cur_col, cache.last.word) then
      print('use cache', unpack(cache.last.word))
      return
    end
    print('matching')
  else
    cache.changetick = session.changetick
  end

  if cache.markers.current then
    local clear = session:clear_ns(cache.markers.current)
    if clear then
      cache.markers.current = nil
    end
  end

  session:get_matches()
  if vim.tbl_isempty(session.match) or not (session.match.at_cursor or session.next_match) then
    session:verify_searchpairpos()
  end
  if not session.match.at_cursor then
    session:verify_next_match()
  end

  if not session.match.node then
    -- if session.opt.show_current then
    cache.last = session.last
    -- session:draw_markers()
    -- end
    return
  end
  session:get_matchpair()
  set_markers(session.match.is_start_point, session.last, session.markers)

  if cache.markers.parent then
    if session.markers.parent and not vim.deep_equal(cache.markers.parent, session.markers.parent) then
      session:clear_ns(cache.markers.parent)
    end
  end

  cache.markers = session.markers
  cache.last = session.last
  session:draw_markers()
  return true
end

function matchwith.jumping()
  local vcount = vim.v.count1
  if vcount > 1 then
    vim.cmd(('normal! %s%%'):format(vcount))
    return
  end
  if vim.g.matchwith_disable or vim.b.matchwith_disable or vim.tbl_isempty(cache.last.current) then
    vim.cmd('normal! %')
    return
  end
  ---TODO:Need to fix a bug that is causing the switch_statement to not correctly get the range it returns.
  -- if vim.tbl_isempty(cache.last.current) then
  --   return
  -- end
  cache.skip_matching = true
  cache.last.current = { [1] = cache.last.current[2], [2] = cache.last.current[1] }
  local row, scol, _, ecol = unpack(cache.last.current[1])
  local is_start_point = cache.last.current[1][1] < cache.last.current[2][1]
  local word_range = is_start_point and { cache.last.current[1][2], cache.last.current[2][4] }
    or { cache.last.current[2][1], cache.last.current[1][4] }
  cache.last.word = { cache.last.current[1][1], word_range[1], zerobase(word_range[2]) }
  local col = is_start_point and ecol or scol
  set_markers(is_start_point, cache.last, cache.markers)
  api.nvim_win_set_cursor(0, { row + 1, col })
  local session = matchwith.new(row, col)
  local is_clear_ns = session:clear_ns(cache.markers.current)
  if is_clear_ns then
    session:draw_markers()
  end
end

-- Set default highlights
---@pacakege
---@param highlights {[string]: vim.api.keyset.highlight}
local function set_hl(highlights)
  for name, value in pairs(highlights) do
    value['default'] = true
    vim.api.nvim_set_hl(0, name, value)
  end
end

-- Configure Matchwith settings
function matchwith.setup(opts, force)
  if vim.g.loaded_matchwith and not force then
    return
  end

  local hl = require('matchwith.config').set_options(opts)
  if not hl then
    util.notify(UNIQUE_ID, 'Error: Requires arguments', vim.log.levels.ERROR)
    return
  end

  cache.hlgroups = hl.groups
  cache.hldetails = hl.details

  vim.cmd('silent! NoMatchParen')
  set_hl(hl.details)

  if not cache.searchpairs then
    matchwith.set_searchpairs()
  end

  local augroup = vim.api.nvim_create_augroup(UNIQUE_ID, { clear = true })
  util.autocmd('BufEnter', {
    desc = 'Matchwith update the buffer configuration',
    group = augroup,
    callback = function(ev)
      cache.skip_matching = true
      if not vim.b[ev.buf].matchwith_disable and (vim.bo[ev.buf].buftype == '') then
        vim.b[ev.buf].matchwith_disable = vim.tbl_contains(vim.g.matchwith_ignore_buftypes, vim.bo[ev.buf].buftype)
        if not vim.b[ev.buf].matchwith_disable then
          matchwith.set_searchpairs()
        end
      end
    end,
  })
  util.autocmd('BufLeave', {
    desc = 'Matchwith clears the buffer configuration',
    group = augroup,
    callback = function(ev)
      api.nvim_buf_clear_namespace(ev.buf, cache.ns, 0, -1)
      cache = vim.tbl_deep_extend('force', cache, _cache)
    end,
  })
  util.autocmd('Filetype', {
    desc = 'Matchwith ignore filetypes',
    group = augroup,
    callback = function(ev)
      if not vim.b[ev.buf].matchwith_disable then
        vim.b[ev.buf].matchwith_disable = vim.tbl_contains(vim.g.matchwith_ignore_filetypes, ev.match)
      end
    end,
  })
  api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    desc = 'Update matchpair drawing',
    group = augroup,
    callback = function()
      if not (vim.g.matchwith_disable or vim.b.matchwith_disable) then
        timer.debounce(vim.g.matchwith_debounce_time, function()
          matchwith.matching()
        end)
      end
    end,
  })
  api.nvim_create_autocmd({ 'InsertEnter', 'InsertLeave' }, {
    desc = 'Update matchpair drawing',
    group = augroup,
    callback = function()
      if not (vim.g.matchwith_disable or vim.b.matchwith_disable) then
        matchwith.matching()
      end
    end,
  })
  util.autocmd({ 'OptionSet' }, {
    desc = 'Reset matchwith searchpairs',
    group = augroup,
    pattern = { 'matchpairs' },
    callback = function()
      matchwith.set_searchpairs()
    end,
  })
  util.autocmd({ 'ColorScheme' }, {
    desc = 'Reload matchwith hlgroups',
    group = augroup,
    callback = function()
      set_hl(cache.hldetails)
    end,
  }, true)
end

return matchwith
