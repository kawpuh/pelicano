# Pelican

A Neovim plugin for interacting with [Simon Willison's LLM CLI tool](https://github.com/simonw/llm) or other commandline LLM tools.

Includes a simple scratch buffer plugin + a mechanism for streaming results from the LLM CLI tool.

All of the functionality is exposed in [pelican.vim](https://github.com/kawpuh/pelican/blob/master/plugin/pelican.vim). There are no builtin mappings, but there's an example keymap below.

## Demo

![output](https://github.com/user-attachments/assets/8878ebec-9c11-495b-9939-98d0a4a3bea2)

## Requirements

- Neovim 0.5.0 or later
- [llm](https://github.com/simonw/llm) installed and configured.

## Usage

### Commands

Note: commands that interact with visual selection must be bound with the `<cmd>` pseudokey to function as expected.

- `:Scratch` - Create a new Markdown scratch file with a timestamp based name.
- `:OpenLatestScratch` - Open last modified file in scratch folder.
- `:ScratchAddName [name]` - Add a name to the current file. For example, it converts `2023-04-29_15-30-45.md` to `2023-04-29_15-30-45 [name].md`. Works with any file type.
- `:ScratchBranch` - Copy current buffer to a new scratch buffer. If the original filename follows the expected timestamp format with a name (e.g., `2023-04-29_15-30-45 prompt.md`), the name will be preserved in the new scratch file.
- `<cmd>LLM` - Call LLM with the current buffer or range as input. Streams output to a new scratch buffer (first in a vertical split window, then subsequent calls will horizontal split off the first). Can also take command line args as expected. e.g. `<cmd>LLM -m claude-3.7-sonnet<CR>`. Will also add a markdown comment to the first line of the buffer showing this invocation. Note that single quotes should be used for string args, not double quotes. Automatically calls ScratchAddName on the prompt (if 'prompt' isn't already in the filename) and response buffers.
- `<cmd>LLMCommand` - Like the LLM command except the entire command should be passed. e.g. `<cmd>LLMCommand claude -p<CR>`
- `<cmd>LLMPrompt` and `<cmd>LLMCommandPrompt` - Like the above except they use `vim.fn.input` to get args at calltime. This allows you to bind `<cmd>LLMPrompt<CR>` and choose what args to pass each time the command is called.
- `:LLMLogs` - Outputs the result of `llm logs` to a new scratch buffer. Also takes command line args as expected e.g. `:LLMLogs -r`
- `<cmd>YankCodeBlock` - Yank buffer/selection as Markdown code block (wrapped in backticks and labelled with language/filetype).
- `:SelectCodeBlock` - If the cursor is within a Markdown code block, visually select the content of the code block.

### Internal mappings
- `<Plug>PutCodeBlockNewScratch` - Pastes the visual selection (or entire buffer in normal mode) as a Markdown code block to a new Scratch buffer.
- `<Plug>PutCodeBlockLatestScratch` - Like the above, except pastes to the end of the last modified scratch file.

#### Note

Files in the scratch folder autosave with a 1 second debounce.

## Example Keymap

```vim
nnoremap <leader>fn <cmd>Scratch<CR>
nnoremap <leader>fp <cmd>OpenLatestScratch<CR>
noremap <leader>cn <Plug>PutCodeBlockNewScratch<CR>
noremap <leader>cp <Plug>PutCodeBlockLatestScratch<CR>
noremap <leader>cy <cmd>YankCodeBlock<CR>
noremap <leader>llm <cmd>LLMPrompt<CR>
nnoremap <leader>lll :LLMLogs<CR>
nnoremap <leader>llr :LLMLogs -r<CR>
augroup PelicanMarkdown
  au!
  au FileType markdown nnoremap <buffer> <C-m> :SelectCodeBlock<CR>"+y
  au FileType markdown nnoremap <buffer> <localleader>fb :ScratchBranch<CR>
  au FileType markdown nnoremap <buffer> <localleader>fa :ScratchAddName<space>
  au FileType markdown noremap <buffer> <localleader>gg <cmd>LLM -m gemini-2.5-pro<CR>
  au FileType markdown noremap <buffer> <localleader>gf <cmd>LLM -m gemini-2.5-flash<CR>
  au FileType markdown noremap <buffer> <localleader>gc <cmd>LLM -m claude-4-sonnet<CR>
  au FileType markdown noremap <buffer> <localleader>gt <cmd>LLM -m gpt-5 -o reasoning_effort medium<CR>
  au FileType markdown noremap <buffer> <localleader>cc <cmd>LLMCommand claude -p<CR>
augroup end
```

## License

MIT
