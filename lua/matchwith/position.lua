---@class Position
local M = {}
-- M.__index = M

-- function M.new(row, col)
--   return setmetatable({ row, col }, { __index = M })
-- end

---@param row integer
---@param col integer
---@return Range4
function M.to_range4(row, col)
  return { row, col, row, col + 1 }
end

return M
