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
---@param msg string|string[][]
function M.echo(name, subject, msg)
    if type(msg) == 'string' then
        msg = { { msg } }
    end
    api.nvim_echo(
        { { string.format('[%s] %s: ', name, subject) }, unpack(msg) },
        false,
        {}
    )
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

-- Determine whether the specified string is in insert-mode.
---@parame mode string
---@return boolean
function M.is_insert_mode(mode)
    return mode:find('^[i|R]') ~= nil
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
---@field public _closing fun(): boolean
---@field public flash fun(timeout:integer,winid:integer,blend:integer,decay:integer): nil

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
            _closing = function()
                return timer:is_closing()
            end,
            flash = function(wait, winid, blend, decay)
                if not running then
                    running = true
                    timer:start(
                        0,
                        wait,
                        vim.schedule_wrap(function()
                            if not api.nvim_win_is_valid(winid) then
                                return
                            end
                            local blending = api.nvim_get_option_value(
                                'winblend',
                                { win = winid }
                            ) + decay
                            if blending > 100 then
                                blending = 100
                            end
                            api.nvim_set_option_value(
                                'winblend',
                                blending,
                                { win = winid }
                            )
                            if
                                api.nvim_get_option_value(
                                        'winblend',
                                        { win = winid }
                                    )
                                    == 100
                                and timer:is_active()
                            then
                                timer:stop()
                                timer:close()
                                api.nvim_win_close(winid, true)
                            end
                        end)
                    )
                else
                    api.nvim_set_option_value(
                        'winblend',
                        blend,
                        { win = winid }
                    )
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
---@return integer window_handle
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
    return winid
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

-- Flash pair marker
---@param ns integer
---@param hl string Highlight name
---@param blend integer Initial value of winblend
---@param decay integer winblend becay
function M.beacon(ns, hl, blend, decay)
    vim.defer_fn(function()
        local line = api.nvim_get_current_line()
        local _, col = unpack(api.nvim_win_get_cursor(0))
        local charidx = vim.str_utfindex(line, col)
        local charwidth =
            math.min(2, #vim.fn.strcharpart(line, charidx, 1, true))
        local next_charwidth =
            math.min(2, #vim.fn.strcharpart(line, charidx + 1, 1, true))
        local width = next_charwidth == 0 and charwidth * 3
            or charwidth * 2 + next_charwidth
        local opts = vim.tbl_extend('force', float_options, {
            width = width,
            row = vim.fn.winline() - 1,
            col = vim.fn.wincol() - 1 - charwidth,
        })
        local bufnr = api.nvim_create_buf(false, true)
        local winid = api.nvim_open_win(bufnr, false, opts)
        api.nvim_win_set_hl_ns(winid, ns)
        vim.wo[winid].winhl = ('Normal:%s'):format(hl)
        api.nvim_set_option_value('winblend', blend, { win = winid })
        local timer = M.set_timer()
        timer.flash(80, winid, blend, decay)
    end, 0)
end

return M
