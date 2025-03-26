# Pelican

A Neovim plugin for interacting with [Simon Willison's LLM CLI tool](https://github.com/simonw/llm).

## Features

- Send prompts to LLM models directly from Neovim
- Send selected text as context for LLM prompts
- View responses in a separate buffer
- Configure default models and system prompts
- Easy to use with sensible defaults

## Requirements

- Neovim 0.5.0 or later
- [llm](https://github.com/simonw/llm) installed and configured

## Installation

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'username/pelican',
  config = function()
    require('pelican').setup({
      -- Optional configuration here
    })
  end
}
```

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'username/pelican',
  config = function()
    require('pelican').setup({
      -- Optional configuration here
    })
  end
}
```

## Configuration

```lua
require('pelican').setup({
  llm_path = "llm",  -- Path to the llm executable
  default_model = "gpt-4", -- Default model to use (optional)
  default_system_prompt = "You are a helpful assistant", -- Default system prompt (optional)
  default_options = {}, -- Any additional options to pass to llm (optional)
})
```

## Usage

### Commands

- `:LLMPrompt` - Opens an input prompt to send a query to LLM
- `:LLMSelection` - In visual mode, sends the selected text as context along with a prompt

### Default Mappings

Default mappings (can be disabled with `let g:pelican_no_default_mappings = 1`):

Normal mode:
- `<leader>llm` - Opens an input prompt to send a query to LLM

Visual mode:
- `<leader>llm` - Sends the selected text as context along with a prompt

### Custom Mappings

You can define your own mappings using the provided `<Plug>` mappings:

```vim
" Normal mode
nmap <leader>p <Plug>(pelican_prompt)

" Visual mode
vmap <leader>p <Plug>(pelican_selection)
```

## Example Workflow

1. Select text in visual mode
2. Press `<leader>llm`
3. Enter a prompt (e.g., "Explain this code")
4. The selected text will be sent to the LLM with your prompt
5. Results will appear in a new split buffer

## License

MIT