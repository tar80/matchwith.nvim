---@class Matchwith
local matchwith = {}
local compat = require('matchwith.compat')
local helper = require('matchwith.helper')
local render = require('matchwith.render')
local util = require('matchwith.util')
local ts = require('matchwith.treesitter')
local timer = require('matchwith.timer').set_timer()
local api = vim.api
local fn = vim.fn

local UNIQUE_NAME = 'matchwith-nvim'
local with_unique_name = util.name_formatter(UNIQUE_NAME)

local _cache = {
  changetick = 0,
  skip_matching = false,
  last = { word = {}, state = {}, next_match = vim.NIL },
  marker = {},
}

---@class Cache
local cache = vim.deepcopy(_cache)
cache.ns = api.nvim_create_namespace(UNIQUE_NAME)

--[[ NOTE:
-- The cursor position is calculated based on a zero index.
-- Additionally, as of version v0.11.0-dev-1216, the fourth value of Range4 needs to be decremented by 1.
-- (which means that adjustments to the end of the word are necessary)
--]]
-- Adjust the number for 0-based
---@param int integer
---@return integer 0-based integer
local function zerobase(int)
  return int - 1
end

function matchwith.clear_ns(self)
  local clear = false
  local col = self.cur_col
  if self.cur_row ~= cache.last.word[1] or (col < cache.last.word[2]) or (cache.last.word[3] < col) then
    api.nvim_buf_clear_namespace(self.bufnr, cache.ns, cache.marker[1], -1)
    clear = true
  end
  return clear
end

function matchwith.new(is_insert_mode, row, col)
  local self = setmetatable({}, { __index = matchwith })
  self['opt'] = {
    captures = vim.g.matchwith_captures,
    indicator = vim.g.matchwith_indicator,
    sign = vim.g.matchwith_sign,
    symbols = vim.g.matchwith_symbols,
  }
  self['mode'] = api.nvim_get_mode().mode
  self['is_insert_mode'] = is_insert_mode or helper.is_insert_mode(self.mode)
  self['bufnr'] = api.nvim_get_current_buf()
  self['winid'] = api.nvim_get_current_win()
  self['filetype'] = api.nvim_get_option_value('filetype', { buf = self.bufnr })
  self['changetick'] = api.nvim_buf_get_changedtick(self.bufnr)
  self['top_row'] = zerobase(fn.line('w0'))
  self['bottom_row'] = zerobase(fn.line('w$'))
  self['sentence'] = vim.api.nvim_get_current_line()
  self['match'] = {}
  self['next_match'] = vim.NIL
  self['node_ranges'] = {}
  self['marker'] = {}
  self['last'] = vim.deepcopy(_cache.last)
  local pos = api.nvim_win_get_cursor(self.winid)
  self['cur_row'] = row or zerobase(pos[1])
  self['cur_col'] = col or pos[2]
  return self
end

---@param instance Matchwith
---@param tsroot TSNode
---@param queries vim.treesitter.Query
---@return MatchItem,TSNode[],table<integer,Range4>
local function iterate_langtree(instance, tsroot, queries)
  ---@type MatchItem, TSNode|vim.NIL, Range4[]
  local match, next_match, classes = {}, vim.NIL, {}

  ---@type integer
  local node_id
  local iter = queries:iter_matches(tsroot, instance.bufnr, instance.cur_row, instance.cur_row + 1, { all = true })
  for _, matches in iter do
    for id, nodes in pairs(matches) do
      local capture = queries.captures[id]
      if vim.tbl_contains(instance.opt.captures, capture) then
        for _, node in ipairs(nodes) do
          local tsrange = ts.range4(node)
          util.tbl_insert(classes, id, tsrange)
          if tsrange[1] == instance.cur_row then
            if tsrange[2] <= instance.cur_col then
              if tsrange[3] == instance.cur_row and instance.cur_col < tsrange[4] then
                match = { node = node, range = tsrange }
                node_id = id
              end
            elseif next_match == vim.NIL then
              next_match = node
              break
            end
          elseif tsrange[1] > instance.cur_row then
            break
          end
        end
      end
    end
  end
  return match, next_match, classes[node_id] or {}
end

function matchwith.get_matches(self)
  ---@type MatchItem, TSNode|vim.NIL, Range4[]
  local match, next_match, node_ranges = {}, vim.NIL, {}

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
          if not vim.tbl_isempty(match) or (next_match ~= vim.NIL) then
            self.match, self.next_match, self.node_ranges = match, next_match, node_ranges or {}
          end
        end
      end
    end)
  end
end

-- Whether the cursor position is at the node starting point
---@param cur_row integer
---@param current Range4
---@param parent Range4
---@return boolean is_start
local function _is_start_point(cur_row, current, parent)
  if cur_row == parent[1] then
    if parent[1] ~= parent[3] then
      return current[2] >= parent[2]
    else
      return current[4] ~= parent[4]
    end
  end
  return false
end

-- Detect matchpair range
---@param is_start_point IsStartPoint
---@param parent TSNode
---@param node_ranges Range4[]
---@return Range4|nil
local function find_sibling(is_start_point, parent, node_ranges)
  ---@type TSNode?,string
  local node, method
  local child_count = ts.child_count(parent)
  if is_start_point then
    node = parent:child(child_count)
    method = 'prev_sibling'
  else
    node = parent:child(0)
    method = 'next_sibling'
  end
  local first_child_range = node and ts.range4(node)
  for _ = 1, child_count, 1 do
    for _, child_range in ipairs(node_ranges) do
      if not node then
        return first_child_range
      end
      if vim.deep_equal(child_range, ts.range4(node)) then
        return child_range
      end
    end
    node = node[method](node)
  end
  return first_child_range
end

---@param sentence string Text of current line
---@param col integer Cursor column
---@return string[]|nil
local function get_searchpair_options(sentence, col)
  if vim.fn.type(sentence) ~= vim.v.t_blob then
    local charidx = compat.str_utfindex(sentence, helper.utf_encoding(), col, false)
    local char = vim.fn.strcharpart(sentence, charidx, 1)
    return cache.searchpairs.matchpair[char]
  end
end

function matchwith.get_pair_pos(self, searchpair_opts)
  ---@type integer[]
  local pair_pos = {}
  if self.is_insert_mode then
    api.nvim_win_set_cursor(self.winid, { self.cur_row + 1, self.cur_col })
    pair_pos = fn.searchpairpos(unpack(searchpair_opts))
    api.nvim_win_set_cursor(self.winid, { self.cur_row + 1, self.cur_col + 1 })
  else
    pair_pos = fn.searchpairpos(unpack(searchpair_opts))
  end
  return pair_pos
end

function matchwith.verify_searchpairpos(self)
  local has_searchpair = false
  local searchpair_opts = get_searchpair_options(self.sentence, self.cur_col)
  if searchpair_opts then
    local pair_pos = self:get_pair_pos(searchpair_opts)
    if (pair_pos[1] + pair_pos[2]) ~= 0 then
      has_searchpair = true
      local pair_row, pair_col = zerobase(pair_pos[1]), zerobase(pair_pos[2])
      local pair_range = { pair_row, pair_col, pair_row, pair_col + 1 }
      local is_start_point = searchpair_opts[4] == 'nW'
      local adjust_col = self.is_insert_mode and self.cur_col + 3 or self.cur_col + 2
      self.match = {
        range = { self.cur_row, self.cur_col, self.cur_row, self.cur_col + 1 },
        is_start_point = is_start_point,
      }
      self.last = {
        word = { self.cur_row, adjust_col, adjust_col },
        state = { self.match.range, pair_range },
        next_match = vim.NIL,
      }
      self.marker = is_start_point and { self.cur_row, pair_range[3] + 1 } or { pair_range[1], self.cur_row + 1 }
    end
  else
    --[[ NOTE:
    --  This checks whether the match target of matchpairs includes the range from just after the cursor position
    --  to just before the match. Therefore, the starting point is +1 and the ending point is -1.
    --  Additionally, since the starting point is zero-based, it needs to be incremented by +2.
    --]]
    local next_range = self.next_match ~= vim.NIL and ts.range4(self.next_match --[[@as TSNode]])
    local scol = self.cur_col + 2
    local ecol = next_range and next_range[4] - 1 or #self.sentence
    if (ecol - scol) > 0 then
      local sentence = self.sentence:sub(scol, ecol)
      local searchpair = vim.iter(cache.searchpairs.chars):find(function(v)
        return sentence:find(v, 1, true)
      end)
      if searchpair then
        self.next_match = vim.NIL
      end
    end
    self.last = {
      word = { self.cur_row, scol, ecol },
      state = {},
      next_match = self.next_match,
    }
  end
  return has_searchpair
end

function matchwith.get_matchpair(self)
  if not vim.tbl_isempty(self.last.word) then
    return
  end
  local parent = self.match.node:parent()
  if parent then
    if parent:type():find('else', 1, true) then
      parent = parent:parent()
      ---@cast parent -nil
    end
    local parent_range = ts.range4(parent)
    local is_start_point = _is_start_point(self.cur_row, self.match.range, parent_range)

    -- Query.iter_matches may not be able to get the bracket range, so we need to add it
    if parent_range[1] ~= parent_range[3] then
      local bracket_range = is_start_point
          and { parent_range[1], parent_range[2], parent_range[1], parent_range[2] + 1 }
        or { parent_range[3], parent_range[4] - 1, parent_range[3], parent_range[4] }
      table.insert(self.node_ranges, bracket_range)
    end
    local pair_range = find_sibling(is_start_point, parent, self.node_ranges)
    if pair_range then
      self.match.is_start_point = is_start_point
      self.marker = { parent_range[1], parent_range[3] + 1 }
      self.last = {
        word = { self.cur_row, self.match.range[2], zerobase(self.match.range[4]) },
        state = { self.match.range, pair_range },
        next_match = self.next_match,
      }
    end
  end
end

-- Whether the pair's position is on-screen or off-screen
function matchwith.pair_marker_state(self, pair_range)
  local pair_row, pair_scol, pair_ecol = unpack(pair_range)
  local leftcol = fn.winsaveview().leftcol
  local wincol = fn.wincol()
  local win_width = api.nvim_win_get_width(self.winid)
  if api.nvim_get_option_value('list', { win = self.winid }) then
    local extends, precedes = helper.expand_listchars()
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
  if self.match.is_start_point then
    if is_over or (pair_row > self.bottom_row) then
      num = num + 2
    end
  elseif is_over or (pair_row < self.top_row) then
    num = num + 1
  end
  return num
end

function matchwith.draw_markers(self)
  if vim.tbl_isempty(cache.last.state) then
    return
  end
  local word_range = ts.convert_wordrange(cache.last.state[1])
  local pair_range = ts.convert_wordrange(cache.last.state[2])
  local num = self:pair_marker_state(pair_range)
  local hl = num == 0 and cache.hlgroups.ON or cache.hlgroups.OFF
  self:add_marker(hl, word_range)
  self:add_marker(hl, pair_range)
  if not self.is_insert_mode and (fn.foldclosed(self.cur_row + 1) == -1) and (num > 0) then
    self:set_indicator(self.opt.symbols[num])
  end
end

function matchwith.add_marker(self, hlgroup, word_range)
  -- local s = { word_range[1], word_range[2] }
  -- local e = { word_range[1], word_range[3] }
  local opts = {}
  compat.hl_range(self.bufnr, cache.ns, hlgroup, word_range, opts)
end

function matchwith.set_searchpairs()
  local chars, matchpair = {}, {}
  vim.tbl_map(function(v)
    ---@type string,string
    local s1, e1 = unpack(vim.split(v, ':', { plain = true }))
    local s2 = s1 == '[' and '\\[' or s1
    local e2 = e1 == ']' and '\\]' or e1
    matchpair[s1] = { s2, '', e2, 'nW' }
    matchpair[e1] = { s2, '', e2, 'bnW' }
    vim.list_extend(chars, { e1, s1 })
  end, vim.split(vim.bo.matchpairs, ',', { plain = true }))
  cache.searchpairs = { chars = chars, matchpair = matchpair }
end

function matchwith.set_indicator(self, symbol)
  if symbol then
    if self.opt.sign then
      local opts = { sign_hl_group = cache.hlgroups.SIGN or 'Normal', sign_text = symbol, priority = 0 }
      vim.api.nvim_buf_set_extmark(0, cache.ns, self.cur_row, self.cur_col, opts)
    end
    if self.opt.indicator > 0 then
      render.indicator(cache.ns, symbol, self.opt.indicator, self.cur_row, self.cur_col)
    end
  end
end

function matchwith.matching(is_insert_mode, row, col)
  if cache.skip_matching then
    cache.skip_matching = false
    return
  end

  local session = matchwith.new(is_insert_mode, row, col)

  if session.is_insert_mode then
    session.cur_col = session.cur_col - 1

    -- If the cursor digit in insert-mode is 0, processing will stop.
    if session.cur_col < 0 then
      if not vim.tbl_isempty(cache.marker) then
        if session:clear_ns() then
          cache.marker = {}
          cache.last = session.last
        end
      end
      return
    end
  end

  if (session.cur_row == cache.last.word[1]) and (session.changetick == cache.changetick) then
    if
      not vim.tbl_isempty(cache.last.state)
      and cache.last.word[2] <= session.cur_col
      and session.cur_col < cache.last.word[3]
    then
      return
    end
  end

  if not vim.tbl_isempty(cache.marker) then
    if session:clear_ns() then
      cache.marker = {}
    end
  end

  cache.changetick = session.changetick
  session:get_matches()

  if vim.tbl_isempty(session.match) then
    session:verify_searchpairpos()
    if vim.tbl_isempty(session.last.word) then
      return
    end
  end

  session:get_matchpair()

  cache.last = session.last
  cache.marker = session.marker
  session:draw_markers()
  return true
end

function matchwith.jumping()
  local vcount = vim.v.count1
  if vcount > 1 then
    vim.cmd.normal({ ('%s%%'):format(vcount), bang = true })
    return
  end
  if vim.g.matchwith_disable or vim.b.matchwith_disable then
    vim.cmd.normal({ '%', bang = true })
    return
  end
  if vim.tbl_isempty(cache.last.state) then
    if cache.last.next_match == vim.NIL then
      vim.cmd.normal({ '%', bang = true })
      return
    end
    local pos = api.nvim_win_get_cursor(0)
    ---@type boolean?
    local ok
    local node_range = ts.range4(cache.last.next_match --[[@as TSNode]])
    if (node_range[1] + 1) == pos[1] and (pos[2] < node_range[2]) then
      ok = matchwith.matching(false, node_range[1], node_range[2])
    end
    if not ok then
      return
    end
  end
  ---TODO:Need to fix a bug that is causing the switch_statement to not correctly get the range it returns.
  -- if vim.tbl_isempty(cache.last.state) then
  --   return
  -- end
  cache.skip_matching = true
  cache.last.state = { [1] = cache.last.state[2], [2] = cache.last.state[1] }
  local row, scol, _, ecol = unpack(cache.last.state[1])
  local is_start_point = cache.last.state[1][1] < cache.last.state[2][1]
  local col = is_start_point and scol or zerobase(ecol)
  cache.marker = is_start_point and { cache.last.state[1][1], cache.last.state[2][3] + 1 }
    or { cache.last.state[2][1], cache.last.state[1][3] + 1 }
  api.nvim_win_set_cursor(0, { row + 1, col })
  local session = matchwith.new(false, row, scol)
  session.match['is_start_point'] = is_start_point
  if session:clear_ns() then
    session:draw_markers()
  end
  cache.last.word = { cache.last.state[1][1], cache.last.state[1][2], zerobase(cache.last.state[1][4]) }
end

function matchwith.setup(opts, force)
  if vim.g.loaded_matchwith and not force then
    return
  end
  local hl = require('matchwith.config').set_options(opts)
  if not hl then
    vim.notify('Arguments reguired', vim.log.levels.ERROR, { title = UNIQUE_NAME })
    return
  end
  vim.cmd('silent! NoMatchParen')
  helper.set_hl(hl.details)
  cache.hlgroups = hl.groups
  cache.hldetails = hl.details
  if not cache.searchpairs then
    matchwith.set_searchpairs()
  end

  local augroup = vim.api.nvim_create_augroup(UNIQUE_NAME, { clear = true })

  api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    desc = with_unique_name('%s: update matchpair drawing'),
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
    desc = with_unique_name('%s: update matchpair drawing'),
    group = augroup,
    callback = function(ev)
      if not (vim.g.matchwith_disable or vim.b.matchwith_disable) then
        local is_insert_mode = ev.event == 'InsertEnter'
        matchwith.matching(is_insert_mode)
        cache.skip_matching = is_insert_mode
      end
    end,
  })
  api.nvim_create_autocmd('BufEnter', {
    desc = with_unique_name('%s: update buffer configrations'),
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
  api.nvim_create_autocmd('BufLeave', {
    desc = with_unique_name('%s: clear buffer configrations'),
    group = augroup,
    callback = function(ev)
      api.nvim_buf_clear_namespace(ev.buf, cache.ns, 0, -1)
      cache = vim.tbl_deep_extend('force', cache, _cache)
    end,
  })
  api.nvim_create_autocmd('Filetype', {
    desc = with_unique_name('%s: set ignore filetypes'),
    group = augroup,
    callback = function(ev)
      if not vim.b[ev.buf].matchwith_disable then
        vim.b[ev.buf].matchwith_disable = vim.tbl_contains(vim.g.matchwith_ignore_filetypes, ev.match)
      end
    end,
  })
  api.nvim_create_autocmd({ 'OptionSet' }, {
    desc = with_unique_name('%s: reset searchpairs'),
    group = augroup,
    pattern = { 'matchpairs' },
    callback = function()
      matchwith.set_searchpairs()
    end,
  })
  api.nvim_create_autocmd({ 'ColorScheme' }, {
    desc = with_unique_name('%s: reload hlgroups'),
    group = augroup,
    callback = function()
      helper.set_hl(cache.hldetails)
    end,
  })
end

return matchwith
