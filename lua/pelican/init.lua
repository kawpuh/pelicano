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
function M.run_llm(input, options, callback)
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

  local accumulated_output = {}
  local is_complete = false
  vim.system(cmd, {
    text = true,
    stdout = function(err, data)
      if err then
        vim.schedule(function()
          vim.notify("Error running llm: " .. vim.inspect(err), vim.log.levels.ERROR)
        end)
        return
      end
      if data then
        -- Split the data by newlines and add to accumulated_output
        local chunks = vim.split(data, "\n", {plain = true})

        -- Append the first chunk to the last element if it exists
        if #accumulated_output > 0 and #chunks > 0 then
          accumulated_output[#accumulated_output] = accumulated_output[#accumulated_output] .. chunks[1]
          table.remove(chunks, 1)
        end

        -- Add remaining chunks as new lines
        for _, chunk in ipairs(chunks) do
          table.insert(accumulated_output, chunk)
        end

        vim.schedule(function()
          callback(accumulated_output, false) -- false indicates streaming is ongoing
        end)
      end
    end,
    on_exit = function()
      is_complete = true
      vim.schedule(function()
        callback(accumulated_output, true) -- true indicates streaming is complete
      end)
    end
  })
end

-- Get the current visual selection
local function get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line, start_col = start_pos[2], start_pos[3]
  local end_line, end_col = end_pos[2], end_pos[3]

  -- Get the selected lines
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  -- Ensure we have valid selection
  if #lines == 0 then
    return nil
  end

  -- Handle the case of a single line selection
  if #lines == 1 then
    lines[1] = string.sub(lines[1], start_col, end_col)
  else
    -- Handle the case of a multi-line selection
    lines[1] = string.sub(lines[1], start_col)
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
  end

  return table.concat(lines, "\n")
end

-- Display LLM output in a new buffer
local function display_output(output, title)
  -- Create a new buffer for the output
  local buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_name(buf, title or "LLM Output")

  -- Set the lines directly without a header
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)

  -- Open the buffer in a new window
  vim.cmd("vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  return buf, win
end

-- Query llm with the current selection as prompt
function M.query_selection()
  local text = get_visual_selection()
  if not text then
    vim.notify("No text selected", vim.log.levels.ERROR)
    return
  end

  -- Create a buffer to display the output in when it's ready
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_name(buf, "LLM Response (Thinking...)")

  -- Set initial content with just a waiting message
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"Processing your request..."})

  -- Open the buffer in a new window
  vim.cmd("vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  -- Set mappings for the buffer
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':q<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':q<CR>', {noremap = true, silent = true})

  -- Run llm with the selection as the prompt
  local first_update = true

  M.run_llm(text, {}, function(output, is_complete)
    -- Update buffer with output
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win) then
      -- Clear old content on first update
      if first_update then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
        first_update = false
      end

      -- Update the buffer with current content
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)
    else
      -- If buffer was closed, create a new one
      display_output(output, "LLM Response")
    end
  end)
end

-- Send a prompt to llm
function M.send_prompt()
  -- Ask for the prompt
  local prompt = vim.fn.input("Enter prompt: ")
  if prompt == "" then
    return
  end

  -- Create a buffer to display the output in when it's ready
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_name(buf, "LLM Response (Thinking...)")

  -- Set initial content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"# Waiting for LLM response...", "", "Processing your request..."})

  -- Open the buffer in a new window
  vim.cmd("vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  -- Set mappings for the buffer
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':q<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':q<CR>', {noremap = true, silent = true})

  -- Run llm
  local first_update = true

  M.run_llm(prompt, {}, function(output, is_complete)
    -- Update buffer with output
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win) then
      -- Update buffer name based on streaming status
      if not is_complete then
        vim.api.nvim_buf_set_name(buf, "LLM Response (Streaming...)")
      else
        vim.api.nvim_buf_set_name(buf, "LLM Response (Completed)")
      end

      -- Clear old content on first update
      if first_update then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"# LLM Response", ""})
        first_update = false
      end

      -- Update the buffer with current content
      vim.api.nvim_buf_set_lines(buf, 2, -1, false, output)
    else
      -- If buffer was closed, create a new one
      display_output(output, "LLM Response")
    end
  end)
end

return M
