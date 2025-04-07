---@class Matchwith
local Matchwith = {}
Matchwith.__index = Matchwith
local helper = require('matchwith.helper')
local render = require('matchwith.render')
local ts = require('matchwith.treesitter')
local util = require('matchwith.util')

---@class Cache
local Cache

function Matchwith.init_cache(cache)
  Cache = cache
end

--[[ NOTE:
-- The cursor position is calculated based on a zero index.
-- Additionally, as of version v0.11.0-dev-1216, the value of end_column needs to be decremented by 1.
-- (which means that adjustments to the end of the word are necessary)
--]]

-- Adjust the number for 0-based
---@param int integer
---@return integer 0-based integer
local function zerobase(int)
  return int - 1
end

function Matchwith.clear_extmarks(self, scope)
  if scope and not ts.is_range(self.cur_row, self.cur_col, Cache.last.range) then
    vim.api.nvim_buf_del_extmark(self.bufnr, Cache.ns, Cache.markers[scope][1])
    vim.api.nvim_buf_del_extmark(self.bufnr, Cache.ns, Cache.markers[scope][2])
    return true
  end
  return false
end

function Matchwith:new(is_insert_mode)
  ---@class Matchwith
  local Instance = setmetatable({}, self)
  Instance['show_next'] = vim.g.matchwith_show_next
  Instance['is_insert_mode'] = is_insert_mode or helper.is_insert_mode()
  Instance['bufnr'] = vim.api.nvim_get_current_buf()
  Instance['winid'] = vim.api.nvim_get_current_win()
  Instance['winwidth'] = vim.api.nvim_win_get_width(Instance.winid)
  Instance['wincol'] = vim.fn.wincol()
  Instance['leftcol'] = vim.fn.winsaveview().leftcol
  Instance['changetick'] = vim.api.nvim_buf_get_changedtick(Instance.bufnr)
  Instance['top_row'] = zerobase(vim.fn.line('w0'))
  Instance['bottom_row'] = zerobase(vim.fn.line('w$'))
  Instance['sentence'] = vim.api.nvim_get_current_line()
  Instance['line_length'] = math.max(0, zerobase(#Instance.sentence))
  Instance['match'] = { cur = {}, next = {}, parent = {} }
  Instance['last'] = {}
  local ft = vim.api.nvim_get_option_value('filetype', { buf = Instance.bufnr })
  local pos = vim.api.nvim_win_get_cursor(Instance.winid)
  local row, col = zerobase(pos[1]), pos[2]
  col = col - (Instance.is_insert_mode and 1 or 0)
  Instance['filetype'] = vim.treesitter.language.get_lang(ft)
  Instance['cur_row'] = row
  Instance['cur_col'] = col
  if vim.api.nvim_get_option_value('list', { win = Instance.winid }) then
    Instance.winwidth = Instance.winwidth - Cache.extends
    Instance.leftcol = Instance.leftcol + Cache.precedes
  end
  return Instance
end

---@param instance Matchwith
---@param tsroot TSNode
---@param queries vim.treesitter.Query
---@return table MatchItems
local function iterate_langtree(instance, tsroot, queries)
  ---@type MatchItems, TSNode[], table<integer,TSNode[]>
  local match, ancestor_nodes, classes = { cur = {}, next = {}, parent = {} }, {}, {}
  local iter = queries:iter_matches(tsroot, instance.bufnr, instance.cur_row, instance.cur_row + 1, {
    max_start_depth = vim.g.matchwith_depth_limit,
  })
  for _, matches in iter do
    for id, nodes in pairs(matches) do
      if not vim.tbl_isempty(match.next) then
        break
      end
      local capture = queries.captures[id]
      if vim.tbl_contains(Cache.captures, capture) then
        for _, node in ipairs(nodes) do
          local tsrange = ts.range4(node)
          util.tbl_insert(classes, id, node)
          if tsrange[1] < instance.cur_row then
            match.parent = { node = node, range = tsrange, ancestor_nodes = ancestor_nodes }
            table.insert(ancestor_nodes, 1, node)
          elseif tsrange[1] == instance.cur_row then
            if tsrange[2] <= instance.cur_col then
              if tsrange[3] == instance.cur_row and instance.cur_col < tsrange[4] then
                match.cur = { node = node, range = tsrange, ancestor_nodes = classes[id], at_cursor = true }
              else
                match.parent = { node = node, range = tsrange, ancestor_nodes = ancestor_nodes }
                table.insert(ancestor_nodes, 1, node)
                match.prev_end_col = tsrange[4]
              end
            elseif vim.tbl_isempty(match.next) and not match.cur.at_cursor then
              table.insert(ancestor_nodes, 1, node)
              match.next = { node = node, range = tsrange, ancestor_nodes = classes[id] }
              break
            end
          else
            break
          end
        end
      end
    end
  end
  return match
end

function Matchwith:get_matches()
  ---@type vim.treesitter.LanguageTree?
  local parsers = ts.get_parsers(self)
  if parsers then
    parsers:for_each_tree(function(tstree, langtree)
      local language = langtree:lang()
      if language == 'markdown_inline' then
        return
      end
      local tsroot = tstree:root()
      local root_range = ts.range4(tsroot)
      if root_range[1] <= self.cur_row and self.cur_row <= root_range[3] then
        local queries = ts.get_query(language)
        if queries then
          local match = iterate_langtree(self, tsroot, queries)
          self.match = vim.tbl_deep_extend('force', self.match, match)
        end
      end
    end)
  end
end

-- Whether the range is at the TSNode starting point
---@param cur_row integer
---@param current Range4
---@param parent Range4
---@return boolean
local function is_tsnode_start_point(cur_row, current, parent)
  if cur_row == parent[1] then
    if parent[1] ~= parent[3] then
      return current[2] >= parent[2]
    else
      return current[4] ~= parent[4]
    end
  end
  return cur_row ~= parent[3]
end

-- Whether the range is at the matchpair starting point
---@param matchpair string[]
---@return boolean
local function is_searchpair_start_point(matchpair)
  return matchpair[4] == 'nW'
end

-- Find the bracket's node within the scope
---@param parent TSNode
---@param bracket string A character when target node type is bracket
---@return Range4?
local function find_bracket_range(parent, bracket)
  for child in parent:iter_children() do
    if child:type() == bracket then
      return ts.range4(child)
    end
  end
end

-- Detect node range match
---@param is_start_point IsStartPoint
---@param parent TSNode
---@param ancestors Range4[]
---@param bracket? string
---@return Range4?
local function find_sibling(is_start_point, parent, ancestors, bracket)
  if bracket then
    return find_bracket_range(parent, bracket)
  end
  ---@type TSNode?
  local node
  local child_count = ts.child_count(parent)
  if is_start_point then
    node = parent:child(0)
    for _ = 1, child_count, 1 do
      if not node then
        return
      end
      for _, ancestor_node in ipairs(ancestors) do
        if ancestor_node == node then
          return ts.range4(node)
        end
      end
      node = node.next_sibling(node)
    end
    return
  else
    if parent:type():find('else', 1, true) then
      parent = parent:parent() --[[@as TSNode]]
      if not parent then
        return
      end
      child_count = ts.child_count(parent)
    end
    node = parent:child(child_count)
    if node then
      local tsrange = ts.range4(node)
      if tsrange[1] == tsrange[3] then
        return tsrange
      end
    end
  end
end

---@param node TSNode
---@param ancestor_nodes TSNode[]
---@param parenthesis string[]
---@return boolean, Range4[]
local function get_match_ranges(node, ancestor_nodes, parenthesis)
  local start_range = find_sibling(true, node, ancestor_nodes, parenthesis[1])
  if start_range then
    local end_range = find_sibling(false, node, ancestor_nodes, parenthesis[2])
    if end_range then
      return true, { start_range, end_range }
    end
  end
  return false, {}
end

function Matchwith:get_searchpairpos(searchpair_opts, col)
  local pair_pos = { 0, 0 }
  if not ts.is_capture_at_pos('string', self.cur_row, col + 1) then
    local row, actual_col, search_col = self.cur_row + 1, self.cur_col + 1, col
    local saveview = vim.fn.winsaveview()
    vim.api.nvim_win_set_cursor(self.winid, { row, search_col })
    pair_pos = vim.fn.searchpairpos(unpack(searchpair_opts))
    vim.api.nvim_win_set_cursor(self.winid, { row, actual_col })
    vim.fn.winrestview(saveview)
  end
  return pair_pos
end

function Matchwith:store_searchpairpos()
  local start_col = self.match.cur.range and self.match.cur.range[4] + 1 or self.cur_col + 1
  local end_col = self.match.next.range and self.match.next.range[2] + 1 or self.line_length + 1
  if (end_col - start_col) <= 0 and self.filetype ~= 'markdown' then
    return
  end
  local text = self.sentence:sub(start_col, end_col)
  local searchpair
  local shorter = end_col
  vim.iter(Cache.searchpairs.chrs):each(function(chr)
    local match_idx = text:find(chr, 1, true)
    if match_idx and match_idx < shorter then
      searchpair, shorter = chr, match_idx
    end
  end)
  if searchpair then
    local searchpair_opts = Cache.searchpairs.matchpair[searchpair]
    local col = start_col + shorter - 2
    if searchpair_opts then
      local scope = shorter == 1 and 'cur' or 'next'
      local pair_pos = self:get_searchpairpos(searchpair_opts, col)
      if (pair_pos[1] + pair_pos[2]) ~= 0 then
        local pair_row, pair_col = zerobase(pair_pos[1]), zerobase(pair_pos[2])
        local pair_range = { pair_row, pair_col, pair_row, pair_col + 1 }
        local is_start_point = is_searchpair_start_point(searchpair_opts)
        self.match[scope] = {
          at_cursor = scope == 'cur',
          is_start_point = is_start_point,
          range = { self.cur_row, col, self.cur_row, col + 1 },
        }
        self.last = {
          is_start_point = is_start_point,
          scope = scope,
          next = is_start_point and { self.match.next.range, pair_range } or { pair_range, self.match.next.range },
          range = {
            self.cur_row,
            (self.match.prev_end_col or 0),
            self.cur_row,
            col,
          },
        }
        return true
      end
    end
  end
end

-- Get parenthesis from matchpairs
---@param chr string A bracket character
---@param is_start_point boolean
---@return string[] parenthesis, boolean IsStartPoint
local function get_parenthesis(chr, is_start_point)
  local parenthesis = {}
  if chr then
    local matchpair = Cache.searchpairs.matchpair[chr]
    if matchpair then
      local open = matchpair[1]:sub(-1)
      local close = matchpair[3]:sub(-1)
      is_start_point = is_start_point and is_searchpair_start_point(matchpair)
      parenthesis = { open, close }
    end
  end
  return parenthesis, is_start_point
end

function Matchwith:get_prev_end_col(scope)
  local prev_end_col = 0
  local match = scope and self.match[scope]
  if match and match.ancestor_nodes then
    local recent_ancestor = ts.range4(match.ancestor_nodes[#match.ancestor_nodes])
    if recent_ancestor[3] == self.cur_row then
      prev_end_col = recent_ancestor[4]
    end
  end
  return prev_end_col
end

-- Get the ancestor of the current node
---@param row integer
---@param col integer
---@param match MatchItem
---@return boolean, Range4[]
local function get_ancestor_range(row, col, match)
  local is_next, match_ranges
  vim.iter(match.ancestor_nodes):find(function(node)
    local parent = node:parent()
    local node_range = ts.range4(parent)
    local _is_start_point = row == node_range[1]
    local node_type = parent:child(_is_start_point and 0 or ts.child_count(parent)):type()
    local parenthesis = get_parenthesis(node_type, _is_start_point)
    if ts.is_range(row, col, node_range) then
      is_next, match_ranges = get_match_ranges(parent, match.ancestor_nodes, parenthesis)
      if
        is_next
        and ts.is_range(row, col, { match_ranges[1][1], match_ranges[1][2], match_ranges[2][3], match_ranges[2][4] })
      then
        return true
      end
    end
  end)
  return is_next, match_ranges
end

function Matchwith:verify_match()
  --[[ NOTE:
    --  This checks whether the match target of matchpairs includes the range from just the cursor position
    --  to just before the match. Additionally, since the starting point is zero-based, it needs to be incremented by +1.
    --]]
  local is_searchpair = self:store_searchpairpos()
  if is_searchpair then
    return
  end

  local next_range = self.match.next.range

  if next_range then
    next_range[4] = next_range[2]
    next_range[2] = self.match.prev_end_col or 0
    local match = self.match.next
    local parent = match.node:parent()
    if parent then
      local node_type = match.node:type()
      local node_range = ts.range4(parent)
      local _is_start_point = self.cur_row == node_range[1]
      local parenthesis, is_start_point = get_parenthesis(node_type, _is_start_point)
      if is_start_point or ts.is_range(self.cur_row, self.cur_col, parent) then
        local is_next, match_ranges = get_match_ranges(parent, match.ancestor_nodes, parenthesis)
        if is_next then
          next_range[4] = next_range[4] - 1
          self.last = {
            is_start_point = is_start_point,
            scope = 'next',
            next = match_ranges,
            parent = util.value_or_nil(not is_start_point, match_ranges),
            range = next_range,
          }
        end
      end
    end
  end
  if self.match.parent.node and not self.last.parent then
    local match = self.match.parent
    local is_parent, match_ranges = get_ancestor_range(self.cur_row, self.cur_col, match)
    if is_parent then
      if vim.tbl_isempty(self.last) then
        self.last = {
          is_start_point = false,
          scope = 'next',
          next = match_ranges,
          parent = match_ranges,
          range = { self.cur_row, (self.match.prev_end_col or 0), self.cur_row, self.line_length },
        }
      else
        self.last.parent = match_ranges
      end
    end
  end
  if vim.tbl_isempty(self.last) then
    self.last.range = { self.cur_row, 0, self.cur_row, self.line_length }
  end
end

function Matchwith:get_current_match()
  local parent = self.match.cur.node:parent()
  if parent then
    local parent_range = ts.range4(parent)
    local _is_start_point = is_tsnode_start_point(self.cur_row, self.match.cur.range, parent_range)
    local parenthesis, is_start_point = get_parenthesis(self.match.cur.node:type(), _is_start_point)
    local bracket = is_start_point and parenthesis[2] or parenthesis[1]
    local pair_range = find_sibling(not is_start_point, parent, self.match.cur.ancestor_nodes, bracket)
    if pair_range then
      return {
        is_start_point = is_start_point,
        scope = 'cur',
        cur = is_start_point and { self.match.cur.range, pair_range } or { pair_range, self.match.cur.range },
        parent = self.last.parent,
        range = { self.cur_row, self.match.cur.range[2], self.cur_row, zerobase(self.match.cur.range[4]) },
      }
    end
  end
  return {}
end

function Matchwith:pair_marker_direction(pair_range, is_start_point)
  local pair_row, pair_scol, _, pair_ecol = unpack(pair_range)
  local num = 0
  if pair_scol > self.cur_col then
    if pair_scol > (self.cur_col + (self.winwidth - self.wincol)) then
      num = 3
    end
  elseif pair_ecol < self.leftcol then
    num = 6
  end
  local is_offscreen = (num > 0) and (self.cur_row ~= pair_row)
  if is_start_point then
    if is_offscreen or (pair_row > self.bottom_row) then
      num = num + 2
    end
  elseif is_offscreen or (pair_row < self.top_row) then
    num = num + 1
  end
  return num
end

---@param scope nodeScope
---@param top integer
---@param bottom integer
---@return boolean
local function determine_start_point(scope, top, bottom)
  if scope ~= 'parent' then
    return Cache.last.is_start_point
  end
  return top <= Cache.last.parent[1][1] and bottom < Cache.last.parent[2][3]
end

function Matchwith:draw_markers(scope)
  if not Cache.last[scope] then
    return
  end
  local is_start_point = determine_start_point(scope, self.top_row, self.bottom_row)
  local start_range = Cache.last[scope][1]
  local end_range = Cache.last[scope][2]
  if not is_start_point then
    start_range, end_range = end_range, start_range
  end
  local num = self:pair_marker_direction(end_range, is_start_point)
  local hlgroup = num == 0 and Cache.hl[scope].on or Cache.hl[scope].off
  local opts = {}
  if (scope == 'cur') and not self.is_insert_mode and (vim.fn.foldclosed(self.cur_row + 1) == -1) and (num > 0) then
    opts = self:set_indicator(vim.g.matchwith_symbols[num])
  end
  self:add_marker(Cache.markers[scope][1], hlgroup, start_range, opts)
  self:add_marker(Cache.markers[scope][2], hlgroup, end_range)
end

function Matchwith:add_marker(id, hl_group, range, sign_options)
  local opts = {
    id = id,
    end_col = range[4],
    hl_group = hl_group,
    priority = vim.g.matchwith_priority,
    strict = false,
  }
  if sign_options then
    opts = vim.tbl_deep_extend('error', opts, sign_options)
  end
  vim.api.nvim_buf_set_extmark(self.bufnr, Cache.ns, range[1], range[2], opts)
end

function Matchwith:set_indicator(symbol)
  local opts = {}
  if symbol then
    if (vim.g.matchwith_indicator > 0) and self.match.cur.at_cursor then
      render.indicator(Cache.ns, symbol, vim.g.matchwith_indicator, self.cur_row, self.cur_col)
    end
    if vim.g.matchwith_sign then
      opts = { sign_hl_group = Cache.hlgroups.SIGN or 'Normal', sign_text = symbol }
    end
  end
  return opts
end

function Matchwith.matching(is_insert_mode)
  if Cache.skip_matching then
    Cache.skip_matching = false
    return
  end

  local Instance = Matchwith:new(is_insert_mode)

  if Instance.is_insert_mode and Instance.cur_col < 0 then
    if Cache.last.cur then
      local clear = Instance:clear_extmarks('cur')
      if clear then
        Cache.last = { parent = Cache.last.parent }
      end
    end
    return
  end

  -- use cache
  if
    (Instance.changetick == Cache.changetick) and ts.is_range(Instance.cur_row, Instance.cur_col, Cache.last.range)
  then
    -- vim.print({ '[matchwith] use cache ', { Instance.cur_row, Instance.cur_col }, Cache.last.range }) ---TODO: for test
    return
  end

  Cache.changetick = Instance.changetick
  Instance:get_matches()

  if vim.tbl_isempty(Instance.match.cur) then
    Instance:verify_match()
  end

  if vim.g.matchwith_show_parent then
    if Instance.match.parent.node and not Instance.last.parent then
      if Instance.match.cur.node then
        local match_parent = Instance.match.cur.node:parent()
        vim.iter(Instance.match.parent.ancestor_nodes):find(function(node)
          if node:parent() == match_parent then
            table.remove(Instance.match.parent.ancestor_nodes, 1)
          else
            return true
          end
        end)
      end
      local is_parent, match_ranges = get_ancestor_range(Instance.cur_row, Instance.cur_col, Instance.match.parent)
      if is_parent then
        Instance.last.parent = match_ranges
      end
    end
    if not Instance.last.parent then
      Instance:clear_extmarks('parent')
    else
      Cache.last.parent = Instance.last.parent
      Instance:draw_markers('parent')
    end
  end

  if not Instance.match.cur.range and not Instance.last.scope then
    Instance:clear_extmarks(Cache.last.scope)
    Cache.last = Instance.last
    return
  elseif not Instance.show_next then
    Instance:clear_extmarks('cur')
  end

  if not Instance.last.range then
    Instance.last = Instance:get_current_match()
  end

  Cache.last = Instance.last
  if Instance.match.cur.at_cursor or Instance.show_next then
    Instance:draw_markers(Cache.last.scope)
  end

  return true
end

function Matchwith.jumping()
  do
    local vcount = vim.v.count1
    if vcount > 1 then
      vim.cmd.normal({ ('%s%%'):format(vcount), bang = true })
      return
    end
  end
  if vim.g.matchwith_disable or vim.b.matchwith_disable then
    vim.cmd.normal({ '%', bang = true })
    return
  end

  local last_range = Cache.last[Cache.last.scope]

  if not last_range then
    if not Cache.last.parent then
      vim.cmd.normal({ '%', bang = true })
      return
    end
    local pos = vim.api.nvim_win_get_cursor(0)
    ---@type boolean?
    local is_match
    local node_range = Cache.last.parent[2]
    if (node_range[1] + 1) == pos[1] and (pos[2] < node_range[2]) then
      is_match = Matchwith.matching(false)
    end
    if not is_match then
      return
    end
  end
  Cache.skip_matching = true
  Cache.last.is_start_point = not Cache.last.is_start_point
  local conditional_select = util.evaluated_condition(Cache.last.is_start_point, true)
  local range = conditional_select(last_range[1], last_range[2])
  Cache.last.range = conditional_select(
    { last_range[2][1], last_range[2][2], last_range[2][1], zerobase(last_range[1][4]) },
    { last_range[1][1], last_range[1][2], last_range[1][1], zerobase(last_range[2][4]) }
  )
  local col = conditional_select(range[2], zerobase(range[4]))
  vim.api.nvim_win_set_cursor(0, { range[1] + 1, col })
  local session = Matchwith:new(false)
  if not Cache.last.cur then
    Cache.last.cur = Cache.last.next
  end
  session:draw_markers('cur')
end

return Matchwith
