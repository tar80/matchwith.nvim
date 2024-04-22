local api = vim.api
local uv = vim.uv

---@meta util
---@class util
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

---@param highlights {[string]:{[string]:string}}
function M.set_hl(highlights)
  for name, value in pairs(highlights) do
    api.nvim_set_hl(0, name, value)
  end
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
---@field public debounce fun(timeout:integer,callback:fun()): nil
---@field public close fun(): nil

---@return Timer
function M.set_timer()
  local timer = assert(uv.new_timer())
  local running = false
  return setmetatable({}, {
    __index = {
      debounce = function(timeout, callback)
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

---@private
local float_options = {
  relative = 'win',
  height = 1,
  focusable = false,
  noautocmd = true,
  border = false,
  style = 'minimal',
}

-- Show indicator on cursor
---@param text string
---@param timeout integer
---@param row integer
---@param col integer
function M.indicator(text, timeout, row, col)
  local bufnr = api.nvim_create_buf(false, true)
  local opts = vim.tbl_extend('force', float_options, {
    width = 1,
    row = 0,
    col = 0,
    bufpos = { row, col },
  })
  local winid = api.nvim_open_win(bufnr, false, opts)
  api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, { text })
  vim.defer_fn(function()
    api.nvim_win_close(winid, true)
  end, timeout)
end

return M
