if exists('g:loaded_pelican')
  finish
endif
let g:loaded_pelican = 1

lua require('pelican')

command! -nargs=* -range=% -bar LLM lua require('pelican').handle_command(<line1>, <line2>, vim.fn.mode(), <q-args>)
command! -nargs=* LLMLogs lua require('pelican').handle_logs_command(<q-args>)
command! -nargs=0 Scratch lua require('pelican.scratch').create_scratch_file()
command! -nargs=0 OpenLatestScratch lua require('pelican.scratch').open_latest_scratch()
command! -nargs=0 SelectCodeBlock lua require('pelican.scratch').select_within_code_block()
lua vim.api.nvim_create_user_command('YankCodeBlock', require('pelican.scratch').yank_as_codeblock, {range = '%'})
lua require('pelican.scratch').setup_scratch_autosave()
