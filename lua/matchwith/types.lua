---@alias Highlights 'Matchwith'|'MatchwithOut'
---@alias WordRange {[1]:integer,[2]:integer,[3]:integer}
---@alias NodeRange {start_row:integer,start_col:integer,end_row:integer,end_col:integer}
---@alias LastState {[1]:WordRange,[2]:WordRange}|nil
---@alias MatchItem {node:TSNode?,range:Range4}

---@class Options
---@field public highlights {[Highlights]:vim.api.keyset.highlight}
---@field public debounce_time integer
---@field public ignore_filetypes string[]
---@field public ignore_buftypes string[]
---@field public captures string[]
---@field public jump_key? string

---@class Cache
---@field private last_state LastState
---@field private startline? integer
---@field private endline? integer

---@class Instance
---@field public mode string
---@field public bufnr integer
---@field public filetype string
---@field public top_row integer
---@field public bottom_row integer
---@field public cur_row integer
---@field public cur_col integer

---@class Matchwith: Instance
---@field public ns integer
---@field public augroup integer
---@field public opt Options
---@field new fun(self:self):self
---@field clear_ns fun(self:self,startline?:integer,endline?:integer):nil
---@field illuminate fun(self:self):LastState|nil
---@field for_each_captures fun(self:self,tsroot:TSNode,query:vim.treesitter.Query,row:integer,start_col:integer,end_col:integer):MatchItem, Range4[]?
---@field get_matchpair fun(self:self,match:MatchItem,ranges:Range4[]):string, Range4|nil
---@field add_hl fun(self:self,group:Highlights,word_range:WordRange):nil
---@field adjust_col fun(self:self,adjust?:boolean)
---@field matching fun(self:self,adjust?:boolean)
---@field jumping fun(self:self)
---@field setup fun(opts:Matchwith):nil
---@field set_matchpairs fun(self:self):nil

---@class TODO
---@field matchpairs table<integer,string[]>
