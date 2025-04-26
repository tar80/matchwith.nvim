---@class util
local M = {}

-- Returns "value" if the "bool" is true, and "nil" if it is false.
---@generic T ...
---@param bool boolean
---@param ... T
---@return T|nil
function M.value_or_nil(bool, ...)
  return vim.F.ok_or_nil(bool, ...)
end

-- Returns a closure for formatting a message with a given "name".
---@param name string The "name" to be used in the message formatting.
---@return function - A closure that takes a "message" string and returns the formatted message with "name".
function M.name_formatter(name)
  return function(message)
    return (message):format(name)
  end
end

---@alias valueType "string"|number|boolean|table|function|thread|userdata
-- A closure function that returns one of the two arguments based on the type of `value` determined in advance.
---@param value any The value to be evaluated.
---@param validator valueType The type to compare against.
---@return function #A closure that returns <arg1> if "value" matches the type of "validator", otherwise returns <arg2>.
function M.evaluated_condition(value, validator)
  return value == validator and function(t, _)
    return t
  end or function(_, f)
    return f
  end
end

-- Adds an element to a list within a table. If the specified key does not exist, a new key is created.
---@param tbl table The table to which the element will be added.
---@param key string|integer The key under which the list is stored.
---@param ... any The value to be inserted and its position in the list.
---@return nil
function M.tbl_insert(tbl, key, ...)
  local args = { ... }
  local pos, value
  if #args < 2 then
    local idx = tbl[key] and vim.tbl_count(tbl[key]) + 1 or 1
    table.insert(args, 1, idx)
  end
  ---@cast args[1] integer
  pos, value = unpack(args)
  if type(tbl) ~= 'table' then
    tbl = {}
  end
  if not tbl[key] then
    tbl[key] = {}
  end
  table.insert(tbl[key], pos, value)
end

return M
