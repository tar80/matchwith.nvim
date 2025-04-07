--NOTE: This module is provided to ensure compatibility with version 0.11.

local M = {}

---@alias Encoding 'utf-8'|'utf-16'|'utf-32'

local has_next_version = vim.fn.has('nvim-0.12') == 1

---@param name string Argument name
---@param value any Argument value
---@param validator vim.validate.Validator
---@param optional boolean? Argument is optional
---@param message string? message when validation fails
function M.validate(name, value, validator, optional, message)
  if has_next_version then
    vim.validate(name, value, validator, optional, message)
  else
    vim.validate({ name = { value, validator, optional } })
  end
end

local _str_utfindex = vim.str_utfindex

---@param s string
---@param encoding Encoding
---@param index? integer
---@param strict_indexing? boolean
---@return integer
function M.str_utfindex(s, encoding, index, strict_indexing)
  if has_next_version then
    return _str_utfindex(s, encoding, index, strict_indexing)
  else
    return _str_utfindex(s, index)
  end
end

---@param bufnr integer
---@param namespace integer
---@param hlgroup string
---@param word_range Range4
---@param opts table
---@return uv.uv_timer_t?|fun()?|nil
function M.hl_range(bufnr, namespace, hlgroup, word_range, opts)
  if has_next_version then
    local s = { word_range[1], word_range[2] }
    local e = { word_range[1], word_range[3] }
    opts = opts or {}
    return vim.hl.range(bufnr, namespace, hlgroup, s, e, opts)
  else
    return vim.api.nvim_buf_add_highlight(bufnr, namespace, hlgroup, unpack(word_range))
  end
end

return M
