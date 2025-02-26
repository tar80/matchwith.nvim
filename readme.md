# matchwith.nvim

matchwith.nvim is a matchparen and matchit alternative plugin.  
Provides simpler functionality using treesitter.

## Features

Displaying symbols for off-screen match.

![sample](https://github.com/tar80/matchwith.nvim/assets/45842304/82b5a284-f4bc-4c07-838f-dcf77f5bf941)

## Requirements

- Neovim >= 0.10.0

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
require('matchwith.config').setup({
    debounce_time = 100,
    ignore_filetypes = { 'vimdoc' }, -- Suggested items: 'TelescopePrompt', 'TelescopeResults', 'cmp-menu', 'cmp-docs'
    ignore_buftypes = { 'nofile' },
    jump_key = nil, -- e.g. '%'
    indicator = 0,
    sign = false,
    captures = {
        'keyword.function',
        'keyword.repeat',
        'keyword.conditional',
        'punctuation.bracket',
        'constructor',
    },
    symbols = { [1] = '↑', [2] = '↓', [3] = '→', [4] = '↗', [5] = '↘', [6] = '←', [7] = '↖', [8] = '↙' },
})
```
