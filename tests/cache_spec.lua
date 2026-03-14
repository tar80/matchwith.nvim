---@diagnostic disable: redefined-local, undefined-field
local assert = require('luassert')
local stub = require('luassert.stub')

describe('cache', function()
  local Cache

  before_each(function()
    package.loaded['matchwith.cache'] = nil
    package.loaded['matchwith.helper'] = nil
    Cache = require('matchwith.cache')

    vim.g.matchwith_captures = {
      ['*'] = { 'default.capture' },
      lua = { 'lua.capture' },
    }
  end)

  describe('.init()', function()
    it('initialize some values.', function()
      local initial = {
        changetick = 0,
        skip_matching = false,
        last = {},
      }
      local keep = {
        changetick = 1,
        skip_matching = true,
        last = { match = {}, next = {}, parent = {} },
        extends = 10,
      }
      vim.iter(keep):each(function(key, value)
        Cache[key] = value
      end)
      Cache:init()
      assert.are.equal(keep.extends, Cache.extends)
      assert.are.equal(initial.changetick, Cache.changetick)
      assert.are.equal(initial.skip_matching, Cache.skip_matching)
      assert.are.same(initial.last, Cache.last)
    end)

    it('should reset internal state to default values', function()
      Cache.changetick = 10
      Cache.skip_matching = true
      Cache.last = { some = 'data' }

      Cache:init()

      assert.is_equal(0, Cache.changetick)
      assert.is_false(Cache.skip_matching)
      assert.is_table(Cache.last)
      assert.is_nil(next(Cache.last))
    end)
  end)

  describe('.update_captures()', function()
    it('should select lua captures when filetype is lua', function()
      stub(vim.treesitter.language, 'get_lang').returns('lua')

      Cache:update_captures('lua')

      assert.is_equal('lua.capture', Cache.captures[1])
      vim.treesitter.language.get_lang:revert()
    end)

    it('should fallback to default (*) captures for unknown filetypes', function()
      stub(vim.treesitter.language, 'get_lang').returns('unknown')

      Cache:update_captures('unknown')

      assert.is_equal('default.capture', Cache.captures[1])
      vim.treesitter.language.get_lang:revert()
    end)
  end)

  describe('.update_searchpairs()', function()
    it('searchpairs.chrs shold de a list-like table.', function()
      Cache:update_searchpairs()
      local sp = Cache.searchpairs
      assert.is_true(vim.islist(sp.chrs))
    end)

    it('searchpairs.matchpair shold de a dictionary-like table.', function()
      Cache:update_searchpairs()
      local sp = Cache.searchpairs
      assert.is_table(sp.matchpair)
      assert.is_false(vim.islist(sp.matchpair))
    end)

    it('should generate correctly escaped regex from matchpairs for Vim search', function()
      local helper = require('matchwith.helper')
      stub(helper, 'split_option_value').returns({ '(:)', '[:]' })
      Cache:update_searchpairs()
      local sp = Cache.searchpairs
      local paren = sp.matchpair['(']
      assert.is_equal('(', paren[1])
      assert.is_equal('', paren[2])
      assert.is_equal(')', paren[3])
      assert.is_equal('nW', paren[4])

      local bracket = sp.matchpair['[']
      assert.is_equal('\\[', bracket[1])
      assert.is_equal('', bracket[2])
      assert.is_equal('\\]', bracket[3])
      assert.is_equal('nW', bracket[4])

      helper.split_option_value:revert()
    end)

    it('should handle empty matchpairs gracefully', function()
      local helper = require('matchwith.helper')
      stub(helper, 'split_option_value').returns({ '' })

      Cache:update_searchpairs()

      assert.is_table(Cache.searchpairs.chrs)
      assert.is_equal(0, #Cache.searchpairs.chrs)

      helper.split_option_value:revert()
    end)
  end)
end)
