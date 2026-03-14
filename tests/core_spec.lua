---@diagnostic disable: param-type-mismatch, missing-parameter, undefined-field
local assert = require('luassert')
local stub = require('luassert.stub')

describe('core module', function()
  local Matchwith
  local Cache
  local config

  before_each(function()
    package.loaded['matchwith.core'] = nil
    package.loaded['matchwith.cache'] = nil
    package.loaded['matchwith.config'] = nil

    Matchwith = require('matchwith.core')
    Cache = require('matchwith.cache')
    config = require('matchwith.config')
    config.set_options({})
    Cache:init()
    Cache:update_wrap_marker()

    stub(vim.cmd, 'normal')
    stub(vim.api, 'nvim_win_set_cursor')
  end)

  after_each(function()
    vim.cmd.normal:revert()
    vim.api.nvim_win_set_cursor:revert()
  end)

  describe('.new()', function()
    local winwidth = vim.api.nvim_win_get_width(0)

    it('should calculate winwidth correctly with list settings', function()
      vim.wo.list = false
      Cache.extends = 0
      Cache.precedes = 0

      local instance = Matchwith:new()
      assert.are.equal(winwidth, instance.winwidth)

      vim.wo.list = true
      Cache.extends = 1
      Cache.precedes = 1

      instance = Matchwith:new()
      assert.is_number(instance.winwidth)
      assert.is_true(instance.winwidth <= winwidth)
    end)
  end)

  describe('.jumping()', function()
    it('should jump to cached target position and skip matching', function()
      local hl = require('matchwith.config').set_options({})
      Cache = require('matchwith.cache'):setup('matchwith', hl)
      Cache.last = {
        scope = 'cur',
        cur = { { 0, 5, 0, 6 }, { 9, 5, 9, 6 } },
        is_start_point = true,
      }

      local m = Matchwith:new()

      m.cur_row = 0
      m.cur_col = 5

      -- 実行
      assert.has_no_errors(function()
        m:jumping(Cache)
      end)

      assert.stub(vim.api.nvim_win_set_cursor).was_called_with(0, { 10, 5 })
      assert.is_true(Cache.skip_matching)
    end)
  end)

  describe('.matching()', function()
    it('should skip if skip_matching is true', function()
      Cache.skip_matching = true
      local m = Matchwith:new()
      stub(m, 'get_matches')

      m:matching(Cache)

      assert.stub(m.get_matches).was_not_called()
      assert.is_false(Cache.skip_matching)
    end)
  end)
end)
