" Example ftplugin for Lua files
if exists('b:did_pelican_ftplugin')
  finish
endif
let b:did_pelican_ftplugin = 1

" Example of creating a buffer-local mapping for Lua files
nnoremap <buffer> <leader>lld :lua require('pelican').run_llm("Explain this code:\n\n" .. table.concat(vim.fn.getline(1, '$'), '\n'))<CR>

" Example of adding a command specific to Lua files
command! -buffer LLMExplainLua lua require('pelican').run_llm("Explain this Lua code thoroughly, focusing on any non-obvious parts:\n\n" .. table.concat(vim.fn.getline(1, '$'), '\n'))