if exists('g:loaded_pelicano')
  finish
endif
let g:loaded_pelicano = 1

lua require('pelicano')

command! -nargs=* LLM lua require('pelicano').query_visual(<q-args>)
command! -nargs=0 LLMPrompt lua require('pelicano').query_visual(vim.fn.input({prompt = 'LLM Args: ', cancelreturn = vim.NIL}))
command! -nargs=+ LLMCommand lua require('pelicano').query_visual(<q-args>, true)
command! -nargs=0 LLMCommandPrompt lua require('pelicano').query_visual(vim.fn.input({prompt = 'LLM Command: ', cancelreturn = vim.NIL}), true)
command! -nargs=* LLMLogs lua require('pelicano').show_logs(<q-args>)
command! -nargs=0 Scratch lua require('pelicano.scratch').create_scratch_file()
command! -nargs=0 OpenLatestScratch lua require('pelicano.scratch').open_latest_scratch()
command! -nargs=0 SelectCodeBlock lua require('pelicano.scratch').select_within_code_block()
command! -nargs=+ ScratchAddName lua require('pelicano.scratch').add_name_to_file(<q-args>)
command! -nargs=0 ScratchBranch lua require('pelicano.scratch').scratch_branch()
command! -nargs=0 YankCodeBlock lua require('pelicano.scratch').yank_as_codeblock()
noremap <Plug>PutCodeBlockNewScratch <cmd>YankCodeBlock<CR><cmd>Scratch<CR>pGo<CR><Esc>
noremap <Plug>PutCodeBlockLatestScratch <cmd>YankCodeBlock<CR><cmd>OpenLatestScratch<CR>Go<Esc>pGo<Esc>

lua require('pelicano.scratch').setup_scratch_autosave()
