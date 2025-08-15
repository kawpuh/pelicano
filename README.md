# Pelican

A Neovim plugin for interacting with [Simon Willison's LLM CLI tool](https://github.com/simonw/llm).

WARNING: May or may not bother to keep docs updated, but all of the functionality is exposed as commands in [pelican.vim](https://github.com/kawpuh/pelican/blob/master/plugin/pelican.vim)

## Demo

![output](https://github.com/user-attachments/assets/8878ebec-9c11-495b-9939-98d0a4a3bea2)

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

- `:Scratch` - Create a new Markdown scratch file with a timestamp based name.
- `:OpenLatestScratch` - Open last modified file in scratch folder.
- `:ScratchAddName [name]` - Add a name to the current file. For example, it converts `2023-04-29_15-30-45.md` to `2023-04-29_15-30-45 [name].md`. Works with any file type.
- `:ScratchBranch` - Copy current buffer to a new scratch buffer. If the original filename follows the expected timestamp format with a name (e.g., `2023-04-29_15-30-45 prompt.md`), the name will be preserved in the new scratch file.
- `:LLM` - Call LLM with the current buffer or range as input. Streams output to a new scratch buffer (first in a vertical split window, then subsequent calls will horizontal split off the first). Can also take command line args as expected. e.g. `:LLM -m claude-3.7-sonnet`. Will also add a markdown comment to the first line of the buffer showing this invocation. Note that single quotes should be used for string args, not double quotes. Automatically calls ScratchAddName on the prompt (if 'prompt' isn't already in the filename) and response buffers.
- `:LLMLogs` - Outputs the result of `llm logs` to a new scratch buffer. Also takes command line args as expected e.g. `:LLMLogs -r`
- `:YankCodeBlock` - Yank buffer/selection as Markdown code block (wrapped in backticks and labelled with language/filetype).
- `:SelectCodeBlock` - If the cursor is within a Markdown code block, visually select the content of the code block.

#### Note

Files in the scratch folder autosave with a 1 second debounce.

## Example Keymap

```vim
" Paste buffer/visual selection as code block in new scratch file
noremap <leader>cn :<c-u>YankCodeBlock<CR>:Scratch<CR>pGo<CR><Esc>
" Paste buffer/visual selection as code block to end of latest scratch file
noremap <leader>cp :<c-u>YankCodeBlock<CR>:OpenLatestScratch<CR>Go<Esc>pGo<CR><Esc>
" Open ex commandline ready to type cli flags for LLM
noremap <leader>llm :<c-u>LLM<space>
" send buffer/visual selection to gpt-5-thinking-medium
noremap <C-g> :<c-u>LLM -m gpt-5 -o reasoning_effort medium<CR>
" open logs
nnoremap <leader>lll :LLMLogs<CR>
" open log of just the last response
nnoremap <leader>llr :LLMLogs -r<CR>
" send buffer/visual selection to claude code in print mode
nnoremap<localleader>cc :<c-u>LLMCommand claude -p<CR>
augroup PelicanMarkdown
    au!
    " yank content of code block to clipboard
    au FileType markdown nnoremap <buffer> <C-m> :SelectCodeBlock<CR>"+y
augroup end
```

## License

MIT
