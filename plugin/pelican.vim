if exists('g:loaded_pelican')
  finish
endif
let g:loaded_pelican = 1

" Commands
command! -nargs=0 LLMPrompt lua require('pelican').send_prompt()
command! -nargs=0 -range LLMSelection lua require('pelican').query_selection()

" Default mappings (can be overridden by user)
if !exists('g:pelican_no_default_mappings')
  " Normal mode mapping for prompt
  nnoremap <silent> <Plug>(pelican_prompt) :LLMPrompt<CR>
  
  " Visual mode mapping for selection
  vnoremap <silent> <Plug>(pelican_selection) :LLMSelection<CR>
  
  " Apply default mappings if user hasn't mapped them already
  if !hasmapto('<Plug>(pelican_prompt)')
    nmap <leader>llm <Plug>(pelican_prompt)
  endif
  
  if !hasmapto('<Plug>(pelican_selection)')
    vmap <leader>llm <Plug>(pelican_selection)
  endif
endif