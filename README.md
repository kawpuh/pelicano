# Pelican

A Neovim plugin for interacting with [Simon Willison's LLM CLI tool](https://github.com/simonw/llm).

## Features

- Basically a simple scratch buffer plugin + a mechanism for streaming results from the LLM CLI tool.

## Requirements

- Neovim 0.5.0 or later
- [llm](https://github.com/simonw/llm) installed and configured

## Configuration

```lua
require('pelican').setup({
  llm_path = "llm",  -- Path to the llm executable
})
```

## Usage

### Commands

- `:Scratch` - Creates a new scratch file
- `:OpenLatestScratch`
- `:LLM` - Call LLM with the current buffer or visual selection as input. Can also take command line args as expected. e.g. `:LLM -m claude-3.7-sonnet`

### Default Mappings

Default mappings (can be disabled with `let g:pelican_no_default_mappings = 1`):

- `<leader>llm` - Opens `:LLM` ready for you to type command line args
- `<C-g>` - Calls `:LLM`

## License

MIT
