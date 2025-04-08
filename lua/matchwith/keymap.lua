local M = {}

function M.set_operator(UNIQUE_NAME, Cache)
  ---@param modifier 'i'|'a'
  ---@param is_parent? boolean
  local function operator_matchpair(modifier, is_parent)
    local scope = is_parent and 'parent' or Cache.last.scope
    if scope and Cache.last[scope] then
      local operator = vim.v.operator
      local mode = vim.api.nvim_get_mode().mode
      local match = Cache.last[scope]
      local col = modifier == 'i' and { match[1][4], match[2][2] } or { match[1][2], match[2][4] }
      local range = { from = { match[1][1] + 1, col[1] }, to = { match[2][3] + 1, col[2] } }

      if mode:find('[vV\x16]') then
        vim.api.nvim_buf_set_mark(0, '<', range.from[1], range.from[2], {})
        vim.api.nvim_buf_set_mark(0, '>', range.to[1], range.to[2] - 1, {})
        vim.cmd([[normal! gvo]])
      else
        if operator == 'y' then
          operator = ('"%sy'):format(vim.v.register)
        end
        vim.cmd('normal! \\<Esc>')
        vim.schedule(function()
          local ve_org = vim.wo.virtualedit
          vim.wo.virtualedit = 'onemore'
          vim.api.nvim_buf_set_mark(0, '[', range.from[1], range.from[2], {})
          vim.api.nvim_buf_set_mark(0, ']', range.to[1], range.to[2], {})
          vim.cmd('normal! `[' .. operator .. '`]')
          vim.wo.virtualedit = ve_org
          if operator == 'c' then
            vim.api.nvim_win_set_cursor(0, { range.from[1], range.from[2] })
          end
        end)
      end
    end
  end

  vim.keymap.set({ 'o', 'x' }, '<Plug>(matchwith-operator-i)', function()
    operator_matchpair('i')
  end, { desc = ('%s: select inner matchpair'):format(UNIQUE_NAME) })
  vim.keymap.set({ 'o', 'x' }, '<Plug>(matchwith-operator-a)', function()
    operator_matchpair('a')
  end, { desc = ('%s: select matchpair range'):format(UNIQUE_NAME) })
  vim.keymap.set({ 'o', 'x' }, '<Plug>(matchwith-operator-parent-i)', function()
    operator_matchpair('i', true)
  end, { desc = ('%s: select inner matchpair'):format(UNIQUE_NAME) })
  vim.keymap.set({ 'o', 'x' }, '<Plug>(matchwith-operator-parent-a)', function()
    operator_matchpair('a', true)
  end, { desc = ('%s: select matchpair range'):format(UNIQUE_NAME) })
end

return M
