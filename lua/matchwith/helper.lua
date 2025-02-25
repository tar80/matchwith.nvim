---@meta helper
---@class helper
local M = {}

-- Get the current utf encoding
---@param encoding? string
---@return string encoding
function M.utf_encoding(encoding)
  encoding = string.lower(encoding or vim.bo.fileencoding)
  if encoding == '' then
    encoding = vim.go.encoding
  end
  local has_match = ('utf-16,utf-32'):find(encoding, 1, true) ~= nil
  return has_match and encoding or 'utf-8'
end

-- Expand listchar symbols
---@return integer extends,integer precedes
function M.expand_listchars()
  local listchars = vim.opt.listchars:get()
  local extends = listchars.extends and 1 or 0
  local precedes = listchars.precedes and 1 or 0
  return extends, precedes
end

-- Determine whether the specified string is in insert-mode.
---@param mode? string
---@return boolean
function M.is_insert_mode(mode)
  mode = mode or vim.api.nvim_get_mode().mode
  return mode:find('^[i|R]') ~= nil
end

-- Set default highlights
---@param highlights table<string,vim.api.keyset.highlight>
function M.set_hl(highlights)
  vim.iter(highlights):each(function(name, value)
    local hl = type(value) == 'function' and value() or value
    hl['default'] = true
    vim.api.nvim_set_hl(0, name, hl)
  end)
end

return M
