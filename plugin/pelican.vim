if exists('g:loaded_pelican')
  finish
endif
let g:loaded_pelican = 1

" Load and setup the Lua module
lua require('pelican')

" Commands
command! -nargs=* -range -bar LLM lua require('pelican').handle_command(<line1>, <line2>, vim.fn.mode(), <q-args>)

" Default mappings (can be overridden by user)
if !exists('g:pelican_no_default_mappings')
  " Map visual mode
  vmap <silent> <Plug>(Pelican) :<C-u>LLM<CR>
  if !hasmapto('<Plug>(Pelican)', 'v')
    vmap <leader>llm <Plug>(Pelican)
  endif

  " Map normal mode (will use current line by default, or a specified range)
  nmap <silent> <Plug>(Pelican) :<C-u>%LLM<CR>
  if !hasmapto('<Plug>(Pelican)', 'n')
    nmap <leader>llm <Plug>(Pelican)
  endif
endif
