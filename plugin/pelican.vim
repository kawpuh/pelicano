if exists('g:loaded_pelican')
  finish
endif
let g:loaded_pelican = 1

" Load the Lua functionality
lua require('pelican')

" Commands
command! -nargs=0 -range LLMSelection lua require('pelican').query_selection()

" Default mappings (can be overridden by user)
if !exists('g:pelican_no_default_mappings')
  if !hasmapto('<Plug>(pelican_selection)')
    vmap <leader>llm :LLMSelection<CR>
    nmap <leader>llm :%LLMSelection<CR>
  endif
endif
