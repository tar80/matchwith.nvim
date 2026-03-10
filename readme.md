# matchwith.nvim

`matchwith.nvim` is an alternative to `matchparen` and `matchit`,
provides simpler functionality using treesitter.

## Features

### Off-screen match indicators

Displays symbols for matching pairs that are currently outside the viewport.

![off-screen](https://github.com/tar80/matchwith.nvim/assets/45842304/82b5a284-f4bc-4c07-838f-dcf77f5bf941)

### Node highlighting

Optionally highlight the next capture match or the parent node match.

![show-nodes](https://github.com/user-attachments/assets/877c2f86-1964-4d97-b602-a04bb8c09f91)

### Word highlighting (Optional)

The `word_highlight` feature is a Tree-sitter implementation of LSP reference highlighting.
This feature is implemented in the `word_highlight` branch due to its potential performance impact.

**Options**

- `word_highlight`(boolean): Enable/Disable the feature.
  default: `true`
- `avoid_word_type`(string[]): Specifies nodes to be excluded.
  default: `{ 'comment', 'string', 'codeblock', 'heading', 'delimiter' }`

![word-highlight](https://github.com/user-attachments/assets/220d2481-b27e-4114-82c0-a31cf917eadd)

## Requirements

- Neovim >= 0.11.0

## Installation

- lazy.nvim

```lua:
{
  'tar80/matchwith.nvim',
  opts = {
    -- see Configuration section for available options
  },
}
```

## Configuration

Default values:

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
    ignore_filetypes = { 'vimdoc' }, -- e.g. 'TelescopePrompt', 'fidget', 'snacks_picker_input'
    ignore_parsers = { 'markdown' },
    indicator = 0,
    jump_key = nil, -- e.g. '%'
    priority = 100,
    show_next = false,
    show_parent = false,
    sign = false,
    symbols = { '↑', '↓', '→', '↗', '↘', '←', '↖', '↙' },
    -- word_highlight branch only
    word_highlight = true,
    avoid_word_type = { 'comment', 'string', 'codeblock', 'heading', 'delimiter' }
})
```

## Highlight Groups

You can customize colors by overriding these highlight groups:

- Matchwith: Current matchpair highlight.
- MatchwithOut: Current matchpair when off-screen.
- MatchwithNext: Next matchpair highlight.
- MatchwithParent: Parent node match highlight.
- MatchwithSign: Indicator in the sign column.
- MatchwithWord: Word highlighting (word_highlight branch).

## Operator keys

matchwith.nvim provides <Plug> maps for selecting ranges:

- <Plug>(matchwith-operator-i): Inner range of the current/next matchpair
- <Plug>(matchwith-operator-a): A range (inclusive) of the current/next matchpair
- <Plug>(matchwith-operator-parent-i): Inner range of the parent matchpair
- <Plug>(matchwith-operator-parent-a): A range (inclusive) of the parent matchpair

### Keymap Example

```lua
vim.keymap.set({'o', 'x'}, 'i%', '<Plug>(matchwith-operator-i)')
vim.keymap.set({'o', 'x'}, 'a%', '<Plug>(matchwith-operator-a)')
vim.keymap.set({'o', 'x'}, 'iP', '<Plug>(matchwith-operator-parent-i)')
vim.keymap.set({'o', 'x'}, 'aP', '<Plug>(matchwith-operator-parent-a)')
```
