local api = vim.api
local uv = vim.uv
local fn = vim.fn

---@meta util
---@class util
local M = {}

---@param name string
---@param message string
---@param errorlevel integer
---@param options? table
function M.notify(name, message, errorlevel, options)
  options = options or {}
  vim.notify(string.format('[%s] %s', name, message), errorlevel, options)
end

---@param name string
---@param subject string
---@param msg table<string,string>[]
function M.echo(name, subject, msg)
  api.nvim_echo({ { string.format('[%s] %s: ', name, subject) }, unpack(msg) }, false, {})
end

-- Adjust the number for 0-based
---@param int integer
---@return integer 0-based integer
function M.zerobase(int)
  return int - 1
end

-- Check the number of characters on the display
---@param string string
---@param column integer
---@return integer charwidth
function M.charwidth(string, column)
  return api.nvim_strwidth(fn.strcharpart(string, column, 1))
end

-- Expand wrapping symbols
---@return integer extends,integer precedes
function M.expand_wrap_symbols()
  local listchars = vim.opt.listchars:get()
  local extends = listchars.extends and 1 or 0
  local precedes = listchars.precedes and 1 or 0
  return extends, precedes
end

-- Insert-mode or not
---@parame mode string
---@return boolean
function M.is_insert_mode(mode)
  return (mode == 'i' or mode == 'R')
end

-- Operator-pending or not
---@param mode? string
function M.is_operator(mode)
  if not mode then
    mode = api.nvim_get_mode().mode
  end
  return mode:find('^no')
end

-- Add element to list. If there is no key in the list, create a new key
---@param ... table, string|integer, integer?, any
function M.tbl_insert(...)
  local args = {...}
  local tbl, key, pos, value
  if #args ~= 4 then
    local idx = args[1][args[2]] and vim.tbl_count(args[1][args[2]]) + 1 or 1
    table.insert(args, 3, idx)
  end
  ---@cast args[3] integer
  tbl, key, pos, value = unpack(args)
  if type(tbl) ~= 'table' then
    tbl = {}
  end
  if not tbl[key] then
    tbl[key] = {}
  end
  table.insert(tbl[key], pos, value)
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
---@field private timer uv.uv_timer_t
---@field private running boolean
---@field public debounce fun(timeout:integer,callback:fun()): nil
---@field public stop fun(): nil
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
          running = false
        end)
      end,
      stop = function()
        if timer and running then
          timer:stop()
          running = false
        end
      end,
      close = function()
        if timer and running then
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
---@param ns integer
---@param text string
---@param timeout integer
---@param row integer
---@param col integer
function M.indicator(ns, text, timeout, row, col)
  local bufnr = api.nvim_create_buf(false, true)
  local opts = vim.tbl_extend('force', float_options, {
    width = 1,
    row = 0,
    col = 0,
    bufpos = { row, col },
  })
  local winid = api.nvim_open_win(bufnr, false, opts)
  api.nvim_win_set_hl_ns(winid, ns)
  api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, { text })
  vim.defer_fn(function()
    api.nvim_win_close(winid, true)
  end, timeout)
end

-- Show indicator on signcolumn
---@param ns integer
---@param row integer
---@param col integer
---@param opts vim.api.keyset.set_extmark
function M.ext_sign(ns, row, col, opts)
  local _opts = { sign_hl_group = 'Normal' }
  opts = vim.tbl_extend('force', _opts, opts)
  api.nvim_buf_set_extmark(0, ns, row, col, opts)
end

return M
