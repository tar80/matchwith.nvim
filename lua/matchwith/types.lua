---@alias Hlgroup 'Matchwith'|'MatchwithOut'
-- Details 1:`row`, 2:`start_row`, 3:`end_row`
---@alias WordRange {[1]:integer,[2]:integer,[3]:integer}
---@alias MatchItem {node:TSNode,range:Range4}
---@alias Last {row:integer|vim.NIL,state:LastState,line:Range4[]}
---@alias LastState {[1]:Range4,[2]:Range4}

---@class Options
---@field public highlights {[Hlgroup]:vim.api.keyset.highlight}
---@field public debounce_time integer
---@field public ignore_filetypes string[]
---@field public ignore_buftypes string[]
---@field public captures string[]
---@field public jump_key? string

---@class Cache
---@field private last Last
---@field private marker_range integer[]
---@field private skip_matching boolean
---@field private changetick integer

---@class Instance
---@field public mode string
---@field public bufnr integer
---@field public filetype string
---@field public top_row integer
---@field public bottom_row integer
---@field public cur_row integer
---@field public cur_col integer
---@field public changetick integer

---@class Matchwith: Instance
---@field public ns integer
---@field public augroup integer
---@field public opt Options
---@field new fun(row?:integer,col?:integer):Matchwith
---@field clear_ns fun(self:self):boolean
---@field get_matches fun(self:self):MatchItem?,Range4[],Range4[]
---@field get_matchpair fun(self:self,match:MatchItem,ranges:Range4[]):Hlgroup, Range4|vim.NIL,integer[]
---@field draw_markers fun(self:self,hlgroup:Hlgroup,match:Range4,pair:Range4):LastState
---@field marker fun(self:self,group:Hlgroup,word_range:WordRange)
---@field adjust_col fun(self:self,adjust?:boolean)
---@field matching fun(row?:integer,col?:integer)
---@field update_markers fun(self:self)
---@field jumping fun(self:self)
---@field setup fun(opts:Matchwith)
---@field set_matchpairs fun(self:self)

---@class TODO
---@field matchpairs table<integer,string[]>
