# matchwith.nvim

matchwith.nvim is an alternative plugin to matchparen and matchit.
Provides simpler functionality using treesitter.

> [!CAUTION]
> We have identified some bugs and are actively working on resolving them.

## Features

Displays off-screen match symbols.

![off-screen](https://github.com/tar80/matchwith.nvim/assets/45842304/82b5a284-f4bc-4c07-838f-dcf77f5bf941)

Highlight the next capture match and parent node match.

![show-nodes](https://github.com/user-attachments/assets/877c2f86-1964-4d97-b602-a04bb8c09f91)

![word-highlight](https://github.com/user-attachments/assets/98c21311-3eae-40e8-a8d5-dce5bafb76b3)

The `word_highlight` feature is a treesitter implementation of LSP reference highlighting.  
This feature can have a significant impact on performance and is therefore implemented
in the `word_highlight` branch.

**Option values**

- `word_highlight`(boolean): Enable/Disable the feature.
  `default: true`
- `avoid_word_type`(string[]): Specifies nodes to be excluded.
  `default: { 'comment', 'string' }`

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

> [!CAUTION]
> The `off_side` option is no longer needed.

```lua
require('matchwith').setup({
    captures = {
        ['*'] = { 'tag.delimiter', 'punctuation.bracket' },
        lua = { 'keyword.function', 'keyword.repeat', 'keyword.conditional', 'keyword.do.matchwith', 'punctuation.bracket', 'constructor' },
        vim = { 'keyword.function', 'keyword.repeat', 'keyword.conditional', 'punctuation.bracket', 'constructor', 'keyword.exception' },
    },
    debounce_time = 50,
    depth_limit = 10,
    ignore_buftypes = { 'nofile' },
    ignore_filetypes = { 'vimdoc' }, -- Suggested items: 'TelescopePrompt', 'TelescopeResults', 'cmp_menu', 'cmp_docs' ,'fidget', 'snacks_picker_input'
    ignore_parsers = { 'markdown' },
    indicator = 0,
    jump_key = nil, -- e.g. '%'
    priority = 100,
    show_next = false,
    show_parent = false,
    sign = false,
    symbols = { [1] = '↑', [2] = '↓', [3] = '→', [4] = '↗', [5] = '↘', [6] = '←', [7] = '↖', [8] = '↙' },
})
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
