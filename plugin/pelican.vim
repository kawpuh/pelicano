if exists('g:loaded_pelican')
  finish
endif
let g:loaded_pelican = 1

" Load and setup the Lua module
lua require('pelican')

" Commands
command! -nargs=* -range=% -bar LLM lua require('pelican').handle_command(<line1>, <line2>, vim.fn.mode(), <q-args>)

" Add scratch file commands
command! -nargs=0 Scratch lua require('pelican.scratch').create_scratch_file()
command! -nargs=0 OpenLatestScratch lua require('pelican.scratch').open_latest_scratch()

" Setup scratch auto-save functionality
lua require('pelican.scratch').setup_scratch_autosave()
