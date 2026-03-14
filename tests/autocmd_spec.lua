---@diagnostic disable: missing-parameter, undefined-field
local assert = require('luassert')
local stub = require('luassert.stub')

describe('autocmd', function()
  local autocmd
  local Cache
  local matchwith_core
  local timer_module
  local UNIQUE_NAME = 'matchwith_test'

  before_each(function()
    package.loaded['matchwith.autocmd'] = nil
    package.loaded['matchwith.core'] = nil
    package.loaded['matchwith.cache'] = nil
    package.loaded['matchwith.timer'] = nil
    package.loaded['matchwith.helper'] = nil

    timer_module = require('matchwith.timer')
    local mock_timer_obj = {
      debounce = stub(),
      close = stub(),
      stop = stub(),
    }
    stub(timer_module, 'set_timer').returns(mock_timer_obj)

    matchwith_core = require('matchwith.core')
    stub(matchwith_core, 'matching')

    Cache = {
      ns = 100,
      disable = false,
      searchpairs = {},
      update_searchpairs = stub(),
      update_captures = stub(),
      init = stub(),
    }

    autocmd = require('matchwith.autocmd')

    vim.g.matchwith_debounce_time = 0
    vim.g.matchwith_ignore_filetypes = {}
  end)

  after_each(function()
    vim.api.nvim_clear_autocmds({ group = UNIQUE_NAME })
    if timer_module.set_timer.revert then
      timer_module.set_timer:revert()
    end
    if matchwith_core.matching.revert then
      matchwith_core.matching:revert()
    end
  end)

  describe('.setup()', function()
    it('should create an augroup and register autocmds', function()
      autocmd.setup(UNIQUE_NAME, Cache)
      local autocommands = vim.api.nvim_get_autocmds({ group = UNIQUE_NAME })
      assert.is_not_nil(autocommands)
      assert.is_true(#autocommands > 0)
    end)
  end)

  describe('OptionSet event', function()
    it('should trigger Cache:update_searchpairs', function()
      autocmd.setup(UNIQUE_NAME, Cache)
      vim.api.nvim_exec_autocmds('OptionSet', {
        group = UNIQUE_NAME,
        pattern = 'matchpairs',
      })
      assert.stub(Cache.update_searchpairs).was_called_with(Cache)
    end)
  end)

  describe('FileType event', function()
    it('should set matchwith_disable for ignored filetypes', function()
      vim.g.matchwith_ignore_filetypes = { 'help' }
      autocmd.setup(UNIQUE_NAME, Cache)

      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_exec_autocmds('FileType', {
        group = UNIQUE_NAME,
        pattern = 'help',
      })

      assert.is_true(vim.b[bufnr].matchwith_disable)
    end)

    it('should update captures for non-ignored filetypes', function()
      vim.g.matchwith_ignore_filetypes = { 'help' }
      autocmd.setup(UNIQUE_NAME, Cache)

      vim.api.nvim_exec_autocmds('FileType', {
        group = UNIQUE_NAME,
        pattern = 'lua',
      })

      assert.stub(Cache.update_captures).was_called_with(Cache, 'lua')
    end)
  end)
end)
