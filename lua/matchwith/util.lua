local api = vim.api
local uv = vim.uv

local M = {}

---@param name string
---@param message string
---@param errorlevel integer
function M.notify(name, message, errorlevel)
  vim.notify(string.format('[%s] %s', name, message), errorlevel)
end

---Adjust the row for 0-based
---@param int integer
---@return integer 0-based integer
function M.zerobase(int)
  return int - 1
  -- return math.max(0, int - 1)
end

---@parame mode string
---@return boolean
function M.is_insert_mode(mode)
  return (mode == 'i' or mode == 'R')
end

---@param tbl table
---@param key string|integer
---@param value any
---@return table<string|integer,table>
function M.tbl_insert(tbl, key, value)
  if type(tbl) ~= 'table' then
    tbl = {}
  end
  if not tbl[key] then
    tbl[key] = {}
  end
  return vim.list_extend(tbl[key], { value })
end

---@param name string|string[]
---@param opts vim.api.keyset.create_autocmd
---@param safestate? boolean
function M.autocmd(name, opts, safestate)
  local callback = opts.callback
  opts.pattern = opts.pattern or '*'
  if safestate then
    opts.callback = function()
      opts.once = true
      opts.callback = callback
      api.nvim_create_autocmd('SafeState', opts)
    end
  end
  api.nvim_create_autocmd(name, opts)
end

---@class Timer
---@field public start fun(): nil
---@field public close fun(): nil

---@param timeout integer
---@param callback fun(): nil
---@return Timer
function M.debounce(timeout, callback)
  local timer = assert(uv.new_timer())
  local running = false
  return setmetatable({}, {
    __index = {
      start = function()
        if not running then
          running = true
        else
          timer:stop()
        end
        timer:start(timeout, 0, function()
          vim.schedule(callback)
        end)
      end,
      close = function()
        if timer then
          timer:stop()
          timer:close()
        end
      end,
    },
  })
end

return M
