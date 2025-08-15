if exists('g:loaded_pelican')
  finish
endif
let g:loaded_pelican = 1

lua require('pelican')

command! -nargs=* -bar LLM lua require('pelican').query_visual(<q-args>)
command! -nargs=+ -bar LLMCommand lua require('pelican').query_visual_with_full_command(<q-args>)
command! -nargs=* LLMLogs lua require('pelican').show_logs(<q-args>)
command! -nargs=0 Scratch lua require('pelican.scratch').create_scratch_file()
command! -nargs=0 OpenLatestScratch lua require('pelican.scratch').open_latest_scratch()
command! -nargs=0 SelectCodeBlock lua require('pelican.scratch').select_within_code_block()
command! -nargs=+ ScratchAddName lua require('pelican.scratch').add_name_to_file(<q-args>)
command! -nargs=0 ScratchBranch lua require('pelican.scratch').scratch_branch()
command! -nargs=0 YankCodeBlock lua require('pelican.scratch').yank_as_codeblock()
lua require('pelican.scratch').setup_scratch_autosave()
