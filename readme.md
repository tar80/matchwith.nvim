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
    ignore_filetypes = { 'vimdoc' }, -- Suggested items: 'TelescopePrompt', 'TelescopeResults', 'cmp_menu', 'cmp_docs' ,'fidget', 'snacks_picker_input'
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

To properly handle HTML and other framework-specific elements,  
consider adding the following options.

> [!NOTE]
> `opts.alter_filetypes` is no longer available. The parser used is automatically determined.

```lua
opts = {
  alter_filetypes -- @deprecated
  captures = {
    javascript = { 'tag.delimiter', 'punctuation.bracket' 'keyword.function', 'keyword.repeat', 'keyword.conditional', 'constructor' },
    html = { 'tag.delimiter', 'punctuation.bracket' },
    svelte = { 'tag.delimiter', 'punctuation.bracket' },
  }
},
```

### Operator keys

Matchwith provides four operator keys corresponding to matchepair.

- `<Plug>(matchwith-operator-i)` Inner range of the current/next matchpair
- `<Plug>(matchwith-operator-a)` A range of the current/next matchpair
- `<Plug>(matchwith-operator-parent-i)` Inner range of the parent matchpair
- `<Plug>(matchwith-operator-parent-a)` A range of the parent matchpair

Register like this:

```lua
vim.keymap.set({'o','x'}, 'i%', '<Plug>(matchwith-operator-i)')
vim.keymap.set({'o','x'}, 'a%', '<Plug>(matchwith-operator-a)')
vim.keymap.set({'o','x'}, 'iP', '<Plug>(matchwith-operator-parent-i)')
vim.keymap.set({'o','x'}, 'aP', '<Plug>(matchwith-operator-parent-a)')
```
