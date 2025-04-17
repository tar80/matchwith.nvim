---@meta helper
---@class helper
local M = {}

---@alias LogLevels 'TRACE'|'DEBUG'|'INFO'|'WARN'|'ERROR'|'OFF'
---@alias UtfEncoding 'utf-8'|'utf-16'|'utf-32'

---@param name string
---@param message string
---@param errorlevel LogLevels
function M.notify(name, message, errorlevel)
  vim.notify(message, vim.log.levels[string.upper(errorlevel)], { title = name })
end

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
---@return integer extends,integer precedes
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

---@param value any
---@return boolean
local function _is_truthy(value)
  return value and tonumber(value) ~= 0
end

---Check the boolean value of user variables set locally/globally
---@param name string
---@return boolean
function M.is_enable_user_vars(name)
  local b = vim.b[name]
  local g = vim.g[name]
  return _is_truthy(b) or _is_truthy(g)
end

local function _value_converter(value)
  local tbl = {}
  local t = type(value)
  if t == 'function' then
    tbl = value()
    return type(tbl) == 'table' and tbl or {}
  elseif t == 'string' then
    return { value }
  elseif t == 'table' then
    for att, _value in pairs(value) do
      local att_t = type(_value)
      if att_t == 'function' then
        _value = _value()
        if _value then
          tbl[att] = _value
        end
      end
      tbl[att] = _value
    end
    return tbl
  end
  return tbl
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
