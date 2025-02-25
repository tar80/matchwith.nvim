local M = {}

---@class Timer
---@field private timer uv.uv_timer_t
---@field private running boolean
---@field public debounce fun(timeout:integer,callback:fun())
---@field public throttle fun(timeout:integer,callback:fun())
---@field public stop fun()
---@field public close fun()
---@field public _closing fun(): boolean

---@return Timer
function M.set_timer()
  local timer = assert(vim.uv.new_timer())
  local running = false
  local last_call_time = 0
  return setmetatable({}, {
    __index = {
      debounce = function(timeout, callback)
        if not running then
          running = true
        else
          timer:stop()
        end
        timer:start(timeout, 0, function()
          running = false
          vim.schedule(callback)
        end)
      end,
      throttle = function(timeout, callback)
        local current_time = vim.uv.now()
        if not running then
          running = true
          timer:start(timeout, 0, function()
            running = false
          end)
        end
        if current_time - last_call_time >= timeout then
          last_call_time = current_time
          vim.schedule(callback)
        end
      end,
      stop = function()
        if timer and running then
          running = false
          timer:stop()
        end
      end,
      close = function()
        if timer then
          running = false
          timer:stop()
          timer:close()
        end
      end,
      _closing = function()
        return timer:is_closing()
      end,
    },
  })
end

return M
