---@class helper
local M = {}

---@alias LogLevels 'TRACE'|'DEBUG'|'INFO'|'WARN'|'ERROR'|'OFF'
---@alias UtfEncoding 'utf-8'|'utf-16'|'utf-32'

-- Get the current utf encoding
---@param encoding? string
---@return string encoding
function M.utf_encoding(encoding)
  encoding = string.lower(encoding or '')
  if encoding == 'utf-8' or encoding == 'utf-16' then
    return encoding
  end
  return 'utf-32'
end

-- Get list of option values
---@param name string vim option name
---@param option? table
---@return string[]
function M.split_option_value(name, option)
  return vim.split(vim.api.nvim_get_option_value(name, option or {}), ',', { plain = true })
end

-- Get the wrap marker status numerically
---@return integer Extends, integer Precedes
function M.get_wrap_marker_flags()
  local listchars = vim.opt.listchars:get()
  local extends = listchars.extends and 1 or 0
  local precedes = listchars.precedes and 1 or 0
  return extends, precedes
end

---@param sentence string
---@return boolean `Blob or not`
function M.is_blob(sentence)
  return vim.fn.type(sentence) == vim.v.t_blob
end

-- Determine whether the specified string is in insert-mode.
---@param mode? string
---@return boolean
function M.is_insert_mode(mode)
  mode = mode or vim.api.nvim_get_mode().mode
  return mode:find('^[i|R]') ~= nil
end

---@param value string|integer
---@return boolean|nil
local function _is_truthy(value)
  return value and tonumber(value) ~= 0
end

---Check the boolean value of user variables set locally/globally
---@param name string
---@return boolean|nil
function M.is_enable_user_vars(name)
  local b = _is_truthy(vim.b[name])
  local g = _is_truthy(vim.g[name])
  if b == false then
    return g or b
  end
  return b or g
end

local function _value_converter(value)
  local t = type(value)
  if t == 'function' then
    local res = value()
    return type(res) == 'table' and res or {}
  end
  if t == 'string' then
    return { value }
  end
  if t == 'table' then
    local tbl = {}
    for att, v in pairs(value) do
      local att_t = (type(v) == 'function' and v() or v)
      if att_t ~= nil then
        tbl[att] = att_t
      end
    end
    return tbl
  end
  return { value }
end

-- Set default highlights
---@param hlgroups table<string,vim.api.keyset.highlight>
function M.set_hl(hlgroups)
  vim.iter(hlgroups):each(function(name, value)
    local hl = _value_converter(value)
    hl['default'] = true
    vim.api.nvim_set_hl(0, name, hl)
  end)
end

return M
