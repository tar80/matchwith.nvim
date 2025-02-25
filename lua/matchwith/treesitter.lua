local M = {}

local ts = vim.treesitter
local tsq = ts.query

---@param language string Query language
---@return vim.treesitter.Query?
function M.get_query(language)
  return tsq.get(language, 'highlights')
end

-- Convert range from Range4 to WordRange(row,scol,ecol)
---@param node TSNode|Range4
---@return WordRange WordRange
function M.convert_wordrange(node)
  local srow, scol, _, ecol = ts.get_node_range(node)
  return { srow, scol, ecol }
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

-- Whether range1 contains range2
---@param range1 Range
---@param range2 Range
---@return boolean
function M.node_contains(range1, range2)
  return ts._range.contains(range1, range2)
end

local has_next_version = vim.fn.has('nvim-0.11') == 1

-- Get the treesitter's language tree parser
---@param instance Instance Matchwith current session
function M.get_parsers(instance)
  ---@type vim.treesitter.LanguageTree?
  local lang_tree
  if ts._get_parser then
    lang_tree = ts._get_parser(instance.bufnr, instance.filetype)
  else
    -- TODO: Should handle get_parser return value change in neovim 12.
    if has_next_version then
      lang_tree = ts.get_parser(instance.bufnr, instance.filetype, { error = false })
    else
      local ok ---@type boolean
      ok, lang_tree = pcall(ts.get_parser, instance.bufnr, instance.filetype)
      if not ok then
        return
      end
    end
  end
  return lang_tree
end

return M
