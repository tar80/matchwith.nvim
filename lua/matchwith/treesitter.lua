local M = {}

local ts = vim.treesitter

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
function M.is_range(row, col, range)
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

-- Get the treesitter's language tree parser
---@param instance Instance Matchwith current session
function M.get_parsers(instance)
  ---@type vim.treesitter.LanguageTree?
  return ts._get_parser and ts._get_parser(instance.bufnr, instance.language)
    or ts.get_parser(instance.bufnr, instance.language, { error = false })
end

---@param name string
---@param row integer
---@param col integer
---@return true?
function M.is_capture_at_pos(name, row, col)
  local bufnr = vim.api.nvim_get_current_buf()
  local buf_highlighter = ts.highlighter.active[bufnr]
  if not buf_highlighter then
    -- local syntax_name = vim.fn.synIDattr(vim.fn.synID(row, col + 1, 1), 'name')
    -- return syntax_name:find('string', 1, true) and true
    return
  end
  local has_capture
  buf_highlighter.tree:for_each_tree(function(tstree, tree)
    if not tstree then
      return
    end
    local language = tree:lang()
    if language == 'markdown_inline' then
      return
    end
    local root = tstree:root()
    local root_start_row, _, root_end_row, _ = root:range()
    -- Only worry about trees within the line range
    if root_start_row > row or root_end_row < row then
      return
    end
    local q = buf_highlighter:get_query(language)
    -- Some injected languages may not have highlight queries.
    if not q:query() then
      return
    end
    local iter = q:query():iter_captures(root, buf_highlighter.bufnr, row, row + 1)
    for id, node in iter do
      if ts.is_in_node_range(node, row, col) then
        ---@diagnostic disable-next-line: invisible
        local capture = q._query.captures[id] -- name of the capture in the query
        if capture:find(name, 1, true) then
          has_capture = true
        end
      end
    end
  end)
  return has_capture
end

return M
