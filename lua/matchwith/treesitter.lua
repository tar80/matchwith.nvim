local M = {}

local ts = vim.treesitter

---@param range Range
---@return Range4
local function _convert_range4(range)
  local len = #range
  if len == 6 then
    table.remove(range, 6)
    table.remove(range, 5)
  elseif len == 2 then
    range = { range[1], range[2], range[1], range[2] + 1 }
  end
  ---@cast range Range4
  return range
end

---@param filetype string
---@return string|nil Language-parser-name
function M.get_language(filetype)
  return ts.language.get_lang(filetype)
end

---@param language string Query language
---@return vim.treesitter.Query?
function M.get_highlights_query(language)
  return ts.query.get(language, 'highlights')
end

-- Get the table assigned range
---@param node TSNode
---@return Range4
function M.range4(node)
  return { node:range() }
end

-- Get the number of children of a node
---@param node TSNode
---@return integer child_count
function M.child_count(node)
  return node:child_count() - 1
end

-- Check if line, column is in range
---@param row integer
---@param col integer
---@param range Range4|TSNode
---@return boolean
function M.is_contains(range, row, col)
  if type(range) == 'userdata' then
    range = M.range4(range)
  elseif type(range) ~= 'table' then
    return false
  end
  ---@cast range -TSNode
  return M.node_contains(range, { row, col, row, col + 1 })
end

-- Whether range1 contains range2
---@param range1 Range
---@param range2 Range
---@return boolean
function M.node_contains(range1, range2)
  return ts._range.contains(range1, range2)
end

-- Get the parser for a specific buffer and attaches it to the buffer
---@param bufnr integer
---@param lang string Language parse name
---@param opts table?
---@return vim.treesitter.LanguageTree?
function M.get_parser(bufnr, lang, opts)
  opts = vim.tbl_deep_extend('force', opts, { error = false })
  return ts.get_parser(bufnr, lang, opts)
end

-- Get the smallest named node at the position
---@param root vim.treesitter.LanguageTree|TSNode
---@param range Range
---@param opts vim.treesitter.LanguageTree.tree_for_range.Opts
---@return TSTree?,TSNode?
function M.get_node(root, range, opts)
  range = _convert_range4(range)
  if root.lang then
    local tree = root:tree_for_range(range, opts)
    if tree then
      return tree, tree:root():named_descendant_for_range(unpack(range))
    end
  elseif type(root) == 'userdata' then
    return nil, root:named_descendant_for_range(unpack(range))
  end
end

-- Get the smallest node at the position
---@param tsroot TSNode
---@param range Range
---@param anonymous? boolean
---@return TSNode?,TSNode?
function M.get_smallest_node_at_pos(tsroot, range, anonymous)
  range = _convert_range4(range)
  return anonymous and tsroot:descendant_for_range(unpack(range)) or tsroot:named_descendant_for_range(unpack(range))
end

---Get the text at the position
---@param bufnr integer
---@param node TSNode
---@param top? integer
---@param bottom? integer
---@return string
function M.get_text_at_pos(bufnr, node, top, bottom)
  local s_row, s_col, e_row, e_col = node:range()
  if top then
    s_row = math.max(top, s_row)
  end
  if bottom then
    e_row = math.min(bottom, e_row)
  end
  local lines = vim.api.nvim_buf_get_text(bufnr, s_row, s_col, e_row, e_col, {})
  return table.concat(lines, '\n')
end

return M
