local assert = require('luassert')
local stub = require('luassert.stub')

describe('config module', function()
  local config

  before_each(function()
    vim.g.matchwith_debounce_time = nil
    vim.g.matchwith_priority = nil
    vim.g.matchwith_captures = nil
    vim.g.matchwith_show_next = nil
    vim.g.matchwith_ignore_filetypes = {}

    package.loaded['matchwith.config'] = nil
    config = require('matchwith.config')
  end)

  describe('.set_options()', function()
    it('If an old format captures table is sent, convert it to the new format.', function()
      local captures =
        { 'keyword.function', 'keyword.repeat', 'keyword.conditional', 'punctuation.bracket', 'constructor' }
      local opts = { captures = vim.deepcopy(captures) }
      config.set_options(opts)
      assert.are_same(captures, vim.g.matchwith_captures['*'])
    end)

    it('should set default values when opts is empty', function()
      config.set_options({})

      assert.is_equal(50, vim.g.matchwith_debounce_time)
      assert.is_equal(100, vim.g.matchwith_priority)
      assert.is_false(vim.g.matchwith_show_next)
      assert.is_table(vim.g.matchwith_captures['*'])
    end)

    it('should override default values with user options', function()
      config.set_options({
        debounce_time = 120,
        priority = 500,
        show_next = true,
      })

      assert.is_equal(120, vim.g.matchwith_debounce_time)
      assert.is_equal(500, vim.g.matchwith_priority)
      assert.is_true(vim.g.matchwith_show_next)
    end)

    it('should handle legacy array format captures and notify user', function()
      local notify = stub(vim, 'notify_once')
      config.set_options({
        captures = { 'dummy.capture' },
      })

      assert.is_equal('dummy.capture', vim.g.matchwith_captures['*'][1])
      assert.stub(notify).was_called()
      notify:revert()
    end)

    it('should merge user ignore_filetypes with defaults', function()
      config.set_options({
        ignore_filetypes = { 'my_secret_ft' },
      })

      local ignores = vim.g.matchwith_ignore_filetypes
      assert.is_true(vim.tbl_contains(ignores, 'my_secret_ft'))
      assert.is_true(vim.tbl_contains(ignores, 'vimdoc'))
    end)
  end)

  it('should define highlight groups when called', function()
    config.set_options({})
    local hl = vim.api.nvim_get_hl(0, { name = 'Matchwith' })
    assert.is_not_nil(hl)
  end)
end)
