local M = {}

---@alias Encoding 'utf-8'|'utf-16'|'utf-32'

local _str_utfindex = vim.str_utfindex
local _str_byteindex = vim.str_byteindex

-- This is a wrapper to accommodate future changes
---@param s string
---@param _encoding Encoding
---@param index? integer
---@param _strict_indexing? boolean
function M.str_utfindex(s, _encoding, index, _strict_indexing)
  return _str_utfindex(s, index)
end

-- This is a wrapper to accommodate future changes
---@param s string
---@param encoding Encoding
---@param index? integer
---@param _strict_indexing? boolean
function M.str_byteindex(s, encoding, index, _strict_indexing)
  local use_utf16 = encoding == 'utf-16'
  return _str_byteindex(s, index, use_utf16)
end

return M
