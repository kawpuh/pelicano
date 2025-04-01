local M = {}

-- Configuration with defaults
M.config = {
  llm_path = "llm",            -- Path to the llm executable, default assumes it's in PATH
  default_model = nil,         -- Uses llm's default model
  default_system_prompt = nil, -- Uses llm's default system prompt
  default_options = {},        -- Additional options to pass to llm
}

-- Keep track of running jobs associated with buffers
local running_jobs = {} -- { bufnr = job_id }

-- Setup function to configure the plugin
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)
end

-- Helper function to run llm and get output
-- Returns job_id or nil on immediate error
function M.run_llm(input, options, bufnr, callback)
  options = options or {}

  -- Build command
  local cmd = { M.config.llm_path }

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

  -- Add any other options from config (merged with specific options)
  local merged_options = vim.tbl_deep_extend("force", vim.deepcopy(M.config.default_options), options)
  for k, v in pairs(merged_options) do
    if k ~= "model" and k ~= "system" then
      if type(k) == "number" then -- Positional argument
        table.insert(cmd, tostring(v))
      else -- Named argument
        -- Handle boolean flags (like --stream)
        if v == true then
          table.insert(cmd, "--" .. k)
        elseif v ~= false then -- Add key and value for non-boolean-false values
          table.insert(cmd, "--" .. k)
          table.insert(cmd, tostring(v))
        end
      end
    end
  end

  -- Add prompt/input at the end
  table.insert(cmd, input)

  -- Ensure callback is callable
  if type(callback) ~= "function" then
    vim.notify("Internal error: Invalid callback provided to run_llm", vim.log.levels.ERROR)
    return nil
  end

  local accumulated_output = {}
  local job_id = vim.system(cmd, {
    text = true,
    stdout = function(err, data)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end -- Check buffer validity
        if err then
          vim.notify("Error reading llm stdout: " .. vim.inspect(err), vim.log.levels.ERROR)
          M.stop_job(bufnr) -- Attempt cleanup on error
          return
        end
        if data then
          -- Split the data by newlines and add to accumulated_output
          local chunks = vim.split(data, "\n", { plain = true, trimempty = false }) -- Keep empty lines for structure

          -- Append the first chunk to the last element if it exists and last element doesn't end with newline
          if #accumulated_output > 0 and #chunks > 0 then
              accumulated_output[#accumulated_output] = accumulated_output[#accumulated_output] .. chunks[1]
              table.remove(chunks, 1)
          end

          -- Add remaining chunks as new lines
          for _, chunk in ipairs(chunks) do
            table.insert(accumulated_output, chunk)
          end

          callback(accumulated_output, false) -- false indicates streaming is ongoing
        end
      end)
    end,
    stderr = function(err, data)
       vim.schedule(function()
         if not vim.api.nvim_buf_is_valid(bufnr) then return end -- Check buffer validity
         if err then
           vim.notify("Error reading llm stderr: " .. vim.inspect(err), vim.log.levels.ERROR)
           M.stop_job(bufnr)
           return
         end
         if data and data ~= "" then
           vim.notify("LLM stderr: " .. data, vim.log.levels.WARN)
         end
       end)
    end,
    on_exit = function(j_id, code, event)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end -- Check buffer validity
        if code ~= 0 then
            vim.notify("llm exited with code " .. code, vim.log.levels.WARN)
        end
        callback(accumulated_output, true) -- true indicates streaming is complete
        running_jobs[bufnr] = nil -- Stop tracking finished job
      end)
    end
  })

  if not job_id or job_id == 0 or job_id == -1 then
     vim.notify("Failed to start llm process. Command: " .. table.concat(cmd, " "), vim.log.levels.ERROR)
     return nil
  end

  -- Track the running job
  running_jobs[bufnr] = job_id

  return job_id
end

-- Get the current visual selection
local function get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  -- Check if marks are valid (line number > 0)
  if start_pos[2] == 0 or end_pos[2] == 0 then
      return nil, "No visual selection detected."
  end

  local start_line, start_col = start_pos[2], start_pos[3]
  local end_line, end_col = end_pos[2], end_pos[3]

  -- getpos returns byte index, but nvim_buf_get_lines expects 0-indexed lines
  -- and nvim_buf_get_text expects 0-indexed columns (UTF-8 bytes)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  if #lines == 0 then
    return nil, "Selected lines could not be retrieved."
  end

  -- Adjust for visual line mode (V) vs visual char mode (v)
  local mode = vim.fn.mode()
  if mode == "V" or mode == "\22" then -- Visual Line or Visual Block
      -- For line mode, take whole lines
      return table.concat(lines, "\n"), nil
  end

  -- Handle character mode (v)
  -- Multi-line selection adjustments
  if #lines > 1 then
      -- Get text after start_col on first line
      local first_line_text = lines[1]
      local _, byte_idx_start = vim.fn.stridx(first_line_text, start_col -1, 'b')
      lines[1] = string.sub(first_line_text, byte_idx_start + 1)

      -- Get text before end_col on last line (inclusive)
      local last_line_text = lines[#lines]
      local _, byte_idx_end = vim.fn.stridx(last_line_text, end_col -1 , 'b') -- Find byte index of the character *at* end_col
      lines[#lines] = string.sub(last_line_text, 1, byte_idx_end + 1 ) -- Substring includes this byte

  -- Single-line selection adjustment
  elseif #lines == 1 then
      local line_text = lines[1]
      local _, byte_idx_start = vim.fn.stridx(line_text, start_col -1, 'b')
      local _, byte_idx_end = vim.fn.stridx(line_text, end_col - 1, 'b')
      lines[1] = string.sub(line_text, byte_idx_start + 1, byte_idx_end + 1)
  end

  return table.concat(lines, "\n"), nil
end

-- Get text from a given line range
local function get_range_text(start_line, end_line)
  -- Ensure lines are within buffer bounds
  local line_count = vim.api.nvim_buf_line_count(0)
  start_line = math.max(1, start_line)
  end_line = math.min(line_count, end_line)

  if start_line > end_line then
    return nil, "Invalid line range."
  end

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  return table.concat(lines, "\n"), nil
end

-- Core function to process text, display output, and handle streaming
local function process_text(text, title_suffix, options)
  if not text or text == "" then
    vim.notify("No text provided to process.", vim.log.levels.WARN)
    return
  end

  -- Create a new buffer for the output
  local buf = vim.api.nvim_create_buf(true, true)
  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_name(buf, "LLM Response (" .. (title_suffix or "Processing") .. "...)")

  -- Set initial content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Requesting response from LLM..." })
  vim.api.nvim_buf_set_option(buf, 'readonly', true) -- Make read-only initially

  -- Open the buffer in a new vertical split
  local current_win = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local out_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(out_win, buf)
  vim.api.nvim_set_current_win(current_win) -- Focus back on original window

  -- --- Streaming Update Logic ---
  local first_update = true
  local function update_buffer(output_lines, is_complete)
    -- Check if buffer and window still exist before updating
    if not vim.api.nvim_buf_is_valid(buf) then
        -- vim.notify("LLM: Output buffer " .. buf .. " is no longer valid. Stopping updates.", vim.log.levels.INFO)
        M.stop_job(buf) -- Ensure job is stopped if buffer gone
        return
    end

    -- Need to make buffer writable to change lines
    vim.api.nvim_buf_set_option(buf, 'readonly', false)

    if first_update then
        -- Clear the "Processing..." message only on the very first actual data update
        if #output_lines > 0 or is_complete then
             vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
             first_update = false
        end
    end

    -- Update the buffer content
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, output_lines)

    -- Keep cursor at the end of the buffer for streaming effect
    local line_count = vim.api.nvim_buf_line_count(buf)
    pcall(vim.api.nvim_win_set_cursor, out_win, {line_count, 0}) -- Use pcall as window might be closed

    -- Final actions when complete
    if is_complete then
        vim.api.nvim_buf_set_name(buf, "LLM Response (" .. (title_suffix or "Completed") .. ")")
        -- Make buffer read-only again, allow normal movement etc.
         vim.api.nvim_buf_set_option(buf, 'readonly', true)
         vim.api.nvim_buf_set_option(buf, 'modifiable', false) -- Also set modifiable
         -- Clear the job tracking explicitly on completion
         running_jobs[buf] = nil
    else
        -- Still streaming, keep it readonly for safety between updates
        vim.api.nvim_buf_set_option(buf, 'readonly', true)
    end
  end
  -- --- End Streaming Update Logic ---

  -- Run llm with the text as the prompt
  local job_id = M.run_llm(text, options or {}, buf, update_buffer)

  if not job_id then
    -- Handle immediate failure to start job
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_set_option(buf, 'readonly', false)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Error: Could not start LLM process." })
      vim.api.nvim_buf_set_option(buf, 'readonly', true)
      vim.api.nvim_buf_set_option(buf, 'modifiable', false)
    end
  end
end

-- Public function to query with visual selection
function M.query_selection(options)
  local text, err = get_visual_selection()
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  if not text then
    vim.notify("No text selected or selection is empty.", vim.log.levels.WARN)
    return
  end
  process_text(text, "Selection", options)
end

-- Public function to query with a line range
function M.query_range(start_line, end_line, options)
  local text, err = get_range_text(start_line, end_line)
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
   if not text then
    vim.notify("No text in selected range.", vim.log.levels.WARN)
    return
  end
  local title = ("Lines %d-%d"):format(start_line, end_line)
  process_text(text, title, options)
end

-- Parse command line arguments into options table
function M.parse_args(args_str)
  local options = {}

  -- Split by spaces, respecting quoted strings
  local parts = {}
  local in_quotes = false
  local current = ""
  local quote_char = nil

  for i = 1, #args_str do
    local char = args_str:sub(i, i)

    if (char == '"' or char == "'") and (i == 1 or args_str:sub(i-1, i-1) ~= "\\") then
      if not in_quotes then
        in_quotes = true
        quote_char = char
      elseif quote_char == char then
        in_quotes = false
        quote_char = nil
      else
        current = current .. char
      end
    elseif char == " " and not in_quotes then
      if current ~= "" then
        table.insert(parts, current)
        current = ""
      end
    else
      current = current .. char
    end
  end

  if current ~= "" then
    table.insert(parts, current)
  end

  -- Process flags
  local i = 1
  while i <= #parts do
    local part = parts[i]

    if part:sub(1, 2) == "--" then
      local key = part:sub(3)

      -- Handle --key=value format
      local equals_pos = key:find("=")
      if equals_pos then
        local value = key:sub(equals_pos + 1)
        key = key:sub(1, equals_pos - 1)
        options[key] = value
      -- Check if next part is a value (not a flag)
      elseif i < #parts and parts[i+1]:sub(1, 2) ~= "--" then
        options[key] = parts[i+1]
        i = i + 1 -- Skip the value
      else
        -- It's a boolean flag
        options[key] = true
      end
    else
      -- Positional argument
      table.insert(options, part)
    end

    i = i + 1
  end

  return options
end

-- Update handle_command to accept and process args
function M.handle_command(line1, line2, mode, args)
  -- Parse args into options table
  local options = M.parse_args(args or "")

  if mode == 'v' or mode == 'V' or mode == '\22' then -- Visual, line-Visual, or block-Visual
    M.query_selection(options)
  else -- Normal mode with a range
    M.query_range(line1, line2, options)
  end
end

return M

