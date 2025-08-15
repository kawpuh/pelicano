if exists('g:loaded_pelican')
  finish
endif
let g:loaded_pelican = 1

lua require('pelican')

command! -nargs=* LLM lua require('pelican').query_visual(<q-args>)
command! -nargs=0 LLMPrompt lua require('pelican').query_visual(vim.fn.input('LLM Args: '))
command! -nargs=+ LLMCommand lua require('pelican').query_visual_with_full_command(<q-args>)
command! -nargs=0 LLMCommandPrompt lua require('pelican').query_visual_with_full_command(vim.fn.input('LLM Command: '))
command! -nargs=* LLMLogs lua require('pelican').show_logs(<q-args>)
command! -nargs=0 Scratch lua require('pelican.scratch').create_scratch_file()
command! -nargs=0 OpenLatestScratch lua require('pelican.scratch').open_latest_scratch()
command! -nargs=0 SelectCodeBlock lua require('pelican.scratch').select_within_code_block()
command! -nargs=+ ScratchAddName lua require('pelican.scratch').add_name_to_file(<q-args>)
command! -nargs=0 ScratchBranch lua require('pelican.scratch').scratch_branch()
command! -nargs=0 YankCodeBlock lua require('pelican.scratch').yank_as_codeblock()
noremap <Plug>PutCodeBlockNewScratch <cmd>YankCodeBlock<CR><cmd>Scratch<CR>pGo<CR><Esc>
noremap <Plug>PutCodeBlockLatestScratch <cmd>YankCodeBlock<CR><cmd>OpenLatestScratch<CR>Go<Esc>pGo<Esc>

lua require('pelican.scratch').setup_scratch_autosave()
