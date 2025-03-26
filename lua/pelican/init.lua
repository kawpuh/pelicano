local M = {}

-- Configuration with defaults
M.config = {
  llm_path = "llm",  -- Path to the llm executable, default assumes it's in PATH
  default_model = nil, -- Uses llm's default model
  default_system_prompt = nil, -- Uses llm's default system prompt
  default_options = {},  -- Additional options to pass to llm
}

-- Setup function to configure the plugin
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)
end

-- Helper function to run llm and get output
function M.run_llm(input, options)
  options = options or {}

  -- Build command
  local cmd = {M.config.llm_path}

  -- Add model if specified
  local model = options.model or M.config.default_model
  if model then
    table.insert(cmd, "--model")
    table.insert(cmd, model)
  end

  -- Add system prompt if specified
  local system = options.system or M.config.default_system_prompt
  if system then
    table.insert(cmd, "--system")
    table.insert(cmd, system)
  end

  -- Add any other options from config
  for k, v in pairs(M.config.default_options) do
    if type(k) == "number" then
      table.insert(cmd, v)
    else
      table.insert(cmd, "--" .. k)
      if v ~= true then
        table.insert(cmd, tostring(v))
      end
    end
  end

  -- Add any other options passed to this function
  for k, v in pairs(options) do
    if k ~= "model" and k ~= "system" then
      if type(k) == "number" then
        table.insert(cmd, v)
      else
        table.insert(cmd, "--" .. k)
        if v ~= true then
          table.insert(cmd, tostring(v))
        end
      end
    end
  end

  -- Add prompt/input at the end
  table.insert(cmd, input)

  -- Run the command and capture output directly using vim.fn.jobstart for proper shell escaping
  local output_str = vim.fn.system(cmd)

  -- Convert output string to lines
  local output = {}
  for line in string.gmatch(output_str, "[^\r\n]+") do
    table.insert(output, line)
  end

  return output
end

-- Query llm with the current selection
function M.query_selection()
  -- Get selected text
  local text
  -- Don't check mode, just try to get the selection using marks
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line, start_col = start_pos[2], start_pos[3]
  local end_line, end_col = end_pos[2], end_pos[3]

  -- Get the selected lines
  local lines = vim.fn.getline(start_line, end_line)

  -- Ensure we have valid selection
  if #lines == 0 then
    vim.api.nvim_err_writeln("No text selected")
    return
  end

  -- Handle the case of a single line selection
  if #lines == 1 then
    text = string.sub(lines[1], start_col, end_col)
  else
    -- Handle the case of a multi-line selection
    lines[1] = string.sub(lines[1], start_col)
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
    text = table.concat(lines, "\n")
  end

  -- Ask for the prompt
  local prompt = vim.fn.input("Enter prompt: ")
  if prompt == "" then
    return
  end

  -- Combine selected text with the prompt
  local input = prompt .. "\n\n" .. text

  -- Show a notification that we're thinking
  vim.api.nvim_echo({{"LLM is thinking...", "WarningMsg"}}, true, {})

  -- Run llm
  local output = M.run_llm(input)

  -- Create a new buffer for the output
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)

  -- Open the buffer in a new window
  vim.api.nvim_command("vsplit")
  vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf)

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  vim.api.nvim_buf_set_name(buf, "LLM Output")
end

-- Send a prompt to llm
function M.send_prompt()
  -- Ask for the prompt
  local prompt = vim.fn.input("Enter prompt: ")
  if prompt == "" then
    return
  end

  -- Show a notification that we're thinking
  vim.api.nvim_echo({{"LLM is thinking...", "WarningMsg"}}, true, {})

  -- Run llm
  local output = M.run_llm(prompt)

  -- Create a new buffer for the output
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)

  -- Open the buffer in a new window
  vim.api.nvim_command("vsplit")
  vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf)

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  vim.api.nvim_buf_set_name(buf, "LLM Output")
end

return M
