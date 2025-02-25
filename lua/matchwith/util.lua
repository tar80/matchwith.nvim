---@meta util
---@class util
local M = {}

-- Returns a closure for formatting a message with a given "name".
---@param name string The "name" to be used in the message formatting.
---@return function - A closure that takes a "message" string and returns the formatted message with "name".
function M.name_formatter(name)
  return function(message)
    return (message):format(name)
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
