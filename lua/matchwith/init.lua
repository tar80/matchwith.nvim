local api = vim.api
local ts = vim.treesitter
local tsh = ts.highlighter
local util = require('matchwith.util')

local UNIQ_ID = 'Matchwith'
local HL_ON_SCREEN = _G.Matchwith_prepare.hlgroups[1]
local HL_OFF_SCREEN = _G.Matchwith_prepare.hlgroups[2]
local _default_options = {
  debounce_time = 80,
  ignore_filetypes = { 'help' },
  ignore_buftypes = { 'nofile' },
  captures = { 'keyword.function', 'keyword.repeat', 'keyword.conditional', 'punctuation.bracket' },
}

---@class Cache
local _ = {
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
  if _.startline and _.endline then
    api.nvim_buf_clear_namespace(0, self.ns, _.startline, _.endline)
    _.startline = nil
    _.endline = nil
  end
end

-- Get the node at the cursor position
function matchwith.get_node(self, lang)
  local parser = ts.get_parser(self.bufnr, lang)
  local range = { self.cur_row, self.cur_col, self.cur_row, self.cur_col }
  return parser:named_node_for_range(range)
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

-- Illuminate a matchpair
function matchwith.illuminate(self)
  local highlighter = tsh.active[self.bufnr]
  if not highlighter then
    return
  end
  local match = {}
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
    local hltree = highlighter:get_query(tslang)
    -- Some injected languages may not have highlight queries.
    if not hltree:query() then
      return
    end
    local has_node, capture =
      self:for_each_captures(self.opt.captures, tsroot, hltree, self.cur_row, self.cur_col, self.cur_col + 1)
    if has_node and capture then
      local word_range1 = self.adjust_range(has_node)
      local off_screen, tsrange = self:get_pair_details(tslang, word_range1)
      local hlgroup = off_screen and HL_OFF_SCREEN or HL_ON_SCREEN
      has_node = self:for_each_captures(capture, tsroot, hltree, unpack(tsrange))
      if has_node then
        local word_range2 = self.adjust_range(has_node)
        self:add_hl(hlgroup, word_range2)
        self:add_hl(hlgroup, word_range1)
        match = {
          [1] = { word_range1.row, word_range1.scol, word_range1.ecol },
          [2] = { word_range2.row, word_range2.scol, word_range2.ecol },
        }
      end
    end
  end)
  return match
end

---Iteratively check if a node has a valid capture
function matchwith.for_each_captures(self, hlgroups, tsroot, hltree, row, start_col, end_col)
  local iter = hltree:query():iter_captures(tsroot, self.bufnr, row, row + 1)
  local cnt = false
  for int, node in iter do
    if node and (cnt or ts.node_contains(node, { row, start_col, row, end_col })) then
      ---@diagnostic disable-next-line: invisible
      local capture = hltree._query.captures[int] -- name of the capture in the query
      if capture then
        for _, hlgroup in ipairs(hlgroups) do
          if hlgroup == capture then
            return node, { capture }
          end
        end
        cnt = #hlgroups == 1
      end
    end
  end
end

function matchwith.adjust_range(match_node)
  local start_row, start_col, end_row, end_col = match_node:range(false)
  if end_col == 0 then
    if start_row == end_row then
      start_col = -1
      start_row = start_row - 1
    end
    end_col = -1
    end_row = end_row - 1
  end
  return { row = start_row, scol = start_col, ecol = end_col }
end

function matchwith.get_pair_details(self, tslang, hlrange)
  local off_screen = true
  local start_row, start_col, end_row, end_col = self:get_node(tslang):range()
  _.startline = start_row
  _.endline = end_row + 1
  local is_start = (self.cur_row == end_row and hlrange.ecol == end_col)
  if is_start then
    if start_row >= self.top_row then
      off_screen = false
    end
    return off_screen, { start_row, start_col, start_col + 1 }
  else
    if end_row <= self.bottom_row then
      off_screen = false
    end
    return off_screen, { end_row, end_col - 1, end_col }
  end
end

function matchwith.add_hl(self, hlgroup, word_range)
  api.nvim_buf_add_highlight(self.bufnr, self.ns, hlgroup, word_range.row, word_range.scol, word_range.ecol)
end

---Update matched pairs
function matchwith.matching(self, adjust)
  if vim.g.matchwith_disable or vim.b.matchwith_disable then
    return
  end
  local session = self:new()
  session:clear_ns()
  session:adjust_col(adjust)
  _.last_state = session:illuminate()
end

function matchwith.jumping()
  local vcount = vim.v.count1
  if vcount > 1 then
    vim.cmd(string.format('normal! %s%%', vcount))
    return
  end
  if vim.tbl_isempty(_.last_state) then
    vim.cmd('normal! %')
    return
  end
  local row, col = unpack(_.last_state[2])
  row = math.min(vim.fn.line('$'), row + 1)
  api.nvim_win_set_cursor(0, { row, col })
  _.last_state = { _.last_state[2], _.last_state[1] }
end

---Set highlights
function matchwith.set_hl(self, highlights)
  for name, value in pairs(highlights) do
    api.nvim_set_hl(0, name, value)
    self.opt.highlights[name] = value
  end
end

---Configure Matchwith settings
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

-- util.autocmd({ 'WinEnter', 'BufEnter', 'BufWritePost' }, {
--   group = matchwith.augroup,
--   desc = 'Update matchpair highlight',
--   callback = function()
--     require('matchwith'):matching()
--   end,
-- }, true)

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

util.autocmd({ 'ColorScheme' }, {
  group = matchwith.augroup,
  desc = 'Reload matchwith hlgroups',
  callback = function()
    require('matchwith'):set_hl(matchwith.opt.highlights)
  end,
}, true)

return matchwith
