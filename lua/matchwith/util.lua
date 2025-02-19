---@meta util
---@class util
local M = {}

-- Add element to list. If there is no key in the list, create a new key
---@param tbl table
---@param key string|integer
---@param ... any
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
