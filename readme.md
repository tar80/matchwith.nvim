# matchwith.nvim

matchwith.nvim is a matchparen and matchit alternative plugin.  
Provides simpler functionality using treesitter.

> [!CAUTION]
> We have confirmed some bugs and are currently working on fixing them.

## Features

Displays off-screen match symbols.

![off-screen](https://github.com/tar80/matchwith.nvim/assets/45842304/82b5a284-f4bc-4c07-838f-dcf77f5bf941)

Highlight the next capture match and parent node match.

![show-nodes](https://github.com/user-attachments/assets/877c2f86-1964-4d97-b602-a04bb8c09f91)

## Requirements

- Neovim >= 0.11.0

## Installation

- lazy.nvim

```lua:
{
  'tar80/matchwith.nvim',
  opts = {
    ...
  },
}
```

## Configuration

Defalut values.

```lua
require('matchwith').setup({
    captures = {
        ['*'] = { 'keyword.function', 'keyword.repeat', 'keyword.conditional', 'punctuation.bracket', 'constructor' },
        off_side = { 'punctuation.bracket' },
    },
    debounce_time = 50,
    depth_limit = 10,
    ignore_buftypes = { 'nofile' },
    ignore_filetypes = { 'vimdoc' }, -- Suggested items: 'TelescopePrompt', 'TelescopeResults', 'cmp_menu', 'cmp_docs' ,'fidget'
    indicator = 0,
    jump_key = nil, -- e.g. '%'
    off_side = { 'query', 'fsharp', 'haskell', 'ocaml', 'make', 'nim', 'python', 'sass', 'scss', 'yaml' },
    priority = 100,
    show_next = false,
    show_parent = false,
    sign = false,
    symbols = { [1] = '↑', [2] = '↓', [3] = '→', [4] = '↗', [5] = '↘', [6] = '←', [7] = '↖', [8] = '↙' },
})
```
