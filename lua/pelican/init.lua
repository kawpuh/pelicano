local M = {}

local scratch = require('pelican.scratch')

M.config = {
  llm_path = "llm",
}

-- Keep track of running jobs associated with buffers
local running_jobs = {}

-- Setup function to configure the plugin
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)
end

local scratch_vsplit_win_id = nil
local function create_scratch_buffer()
  local original_win = vim.api.nvim_get_current_win()

  local target_win_for_split = nil
  local split_command = ''
  local new_win = nil
  local buf = nil

  local vsplit_win_valid = scratch_vsplit_win_id and vim.api.nvim_win_is_valid(scratch_vsplit_win_id)

  if not vsplit_win_valid then
    scratch_vsplit_win_id = nil
    target_win_for_split = original_win
    split_command = 'vsplit'
  else
    target_win_for_split = scratch_vsplit_win_id
    split_command = 'split'
  end

  vim.api.nvim_set_current_win(target_win_for_split)
  vim.cmd(split_command)
  new_win = vim.api.nvim_get_current_win()

  if split_command == 'vsplit' then
    scratch_vsplit_win_id = new_win
  end

  scratch.create_scratch_file()
  buf = vim.api.nvim_get_current_buf()

  -- IMPORTANT: Return focus to the window the user was originally in
  vim.api.nvim_set_current_win(original_win)

  return buf, new_win
end

-- Helper function to run llm and get output
-- Returns job_id or nil on immediate error
function M.run_llm(input, options, bufnr, out_win)
  options = options or {}

  local first_update = true
  local function update_buffer(output_lines, is_complete)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      M.stop_job(bufnr)
      return
    end

    if first_update then
      if #output_lines > 0 or is_complete then
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
        first_update = false
      end
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, output_lines)

    -- Keep cursor at the end of the buffer for streaming effect
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    pcall(vim.api.nvim_win_set_cursor, out_win, { line_count, 0 })

    -- Mark as modified when complete to encourage saving
    if is_complete then
      vim.api.nvim_buf_set_option(bufnr, 'modified', true)
      running_jobs[bufnr] = nil
    end
  end

  local cmd = { M.config.llm_path }

  local model = options.model
  if model then
    table.insert(cmd, "--model")
    table.insert(cmd, model)
  end

  local system = options.system
  if system then
    table.insert(cmd, "--system")
    table.insert(cmd, system)
  end

  local merged_options = vim.tbl_deep_extend("force", {}, options)
  for k, v in pairs(merged_options) do
    if k ~= "model" and k ~= "system" then
      if type(k) == "number" then
        table.insert(cmd, tostring(v))
      else
        if v == true then
          table.insert(cmd, "--" .. k)
        elseif v ~= false then
          table.insert(cmd, "--" .. k)
          table.insert(cmd, tostring(v))
        end
      end
    end
  end

  table.insert(cmd, input)

  local accumulated_output = {}
  local job_id = vim.system(cmd, {
    text = true,
    stdout = function(err, data)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        if err then
          vim.notify("Error reading llm stdout: " .. vim.inspect(err), vim.log.levels.ERROR)
          M.stop_job(bufnr)
          return
        end
        if data then
          local chunks = vim.split(data, "\n", { plain = true, trimempty = false })

          -- Append the first chunk to the last element if it exists and last element doesn't end with newline
          if #accumulated_output > 0 and #chunks > 0 then
            accumulated_output[#accumulated_output] = accumulated_output[#accumulated_output] .. chunks[1]
            table.remove(chunks, 1)
          end

          for _, chunk in ipairs(chunks) do
            table.insert(accumulated_output, chunk)
          end

          update_buffer(accumulated_output, false)
        end
      end)
    end,
    stderr = function(err, data)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
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
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        if code ~= 0 then
          vim.notify("llm exited with code " .. code, vim.log.levels.WARN)
        end
        update_buffer(accumulated_output, true)
        running_jobs[bufnr] = nil
      end)
    end
  })

  if not job_id or job_id == 0 or job_id == -1 then
    vim.notify("Failed to start llm process. Command: " .. table.concat(cmd, " "), vim.log.levels.ERROR)
    return nil
  end

  running_jobs[bufnr] = job_id
  return job_id
end

-- Function to stop a running job
function M.stop_job(bufnr)
  local job_id = running_jobs[bufnr]
  if job_id then
    vim.system({ 'kill', tostring(job_id) })
    running_jobs[bufnr] = nil
  end
end

-- Get the current visual selection
local function get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  if start_pos[2] == 0 or end_pos[2] == 0 then
    return nil, "No visual selection detected."
  end

  local start_line, start_col = start_pos[2], start_pos[3]
  local end_line, end_col = end_pos[2], end_pos[3]

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  if #lines == 0 then
    return nil, "Selected lines could not be retrieved."
  end

  local mode = vim.fn.mode()
  if mode == "V" or mode == "\22" then
    return table.concat(lines, "\n"), nil
  end

  if #lines > 1 then
    local first_line_text = lines[1]
    local _, byte_idx_start = vim.fn.stridx(first_line_text, start_col - 1, 'b')
    lines[1] = string.sub(first_line_text, byte_idx_start + 1)

    local last_line_text = lines[#lines]
    local _, byte_idx_end = vim.fn.stridx(last_line_text, end_col - 1, 'b')
    lines[#lines] = string.sub(last_line_text, 1, byte_idx_end + 1)
  elseif #lines == 1 then
    local line_text = lines[1]
    local _, byte_idx_start = vim.fn.stridx(line_text, start_col - 1, 'b')
    local _, byte_idx_end = vim.fn.stridx(line_text, end_col - 1, 'b')
    lines[1] = string.sub(line_text, byte_idx_start + 1, byte_idx_end + 1)
  end

  return table.concat(lines, "\n"), nil
end

-- Get text from a given line range
local function get_range_text(start_line, end_line)
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
local function process_text(text, options)
  if not text or text == "" then
    vim.notify("No text provided to process.", vim.log.levels.WARN)
    return
  end

  local buf, out_win = create_scratch_buffer()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Requesting response from LLM..." })
  local job_id = M.run_llm(text, options or {}, buf, out_win)

  if not job_id then
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Error: Could not start LLM process." })
      vim.api.nvim_buf_set_option(buf, 'modified', true)
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
  process_text(text, options)
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
  process_text(text, options)
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

    if (char == '"' or char == "'") and (i == 1 or args_str:sub(i - 1, i - 1) ~= "\\") then
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

  local i = 1
  while i <= #parts do
    local part = parts[i]

    if part:sub(1, 2) == "--" then
      local key = part:sub(3)

      local equals_pos = key:find("=")
      if equals_pos then
        local value = key:sub(equals_pos + 1)
        key = key:sub(1, equals_pos - 1)
        options[key] = value
      elseif i < #parts and parts[i + 1]:sub(1, 2) ~= "--" then
        options[key] = parts[i + 1]
        i = i + 1
      else
        options[key] = true
      end
    else
      table.insert(options, part)
    end

    i = i + 1
  end

  return options
end

-- Update handle_command to accept and process args
function M.handle_command(line1, line2, mode, args)
  local options = M.parse_args(args or "")

  if mode == 'v' or mode == 'V' or mode == '\22' then
    M.query_selection(options)
  else
    M.query_range(line1, line2, options)
  end
end

-- Function to show llm logs in a scratch buffer
function M.show_logs(options)
  options = options or {}

  local buf, out_win = create_scratch_buffer()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Loading LLM logs..." })

  local cmd = { M.config.llm_path, "logs" }

  for k, v in pairs(options) do
    if type(k) == "number" then
      table.insert(cmd, tostring(v))
    else
      if v == true then
        table.insert(cmd, "--" .. k)
      elseif v ~= false then
        table.insert(cmd, "--" .. k)
        table.insert(cmd, tostring(v))
      end
    end
  end

  local first_update = true
  local function update_buffer(output_lines, is_complete)
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    if first_update then
      if #output_lines > 0 or is_complete then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
        first_update = false
      end
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, output_lines)

    local line_count = vim.api.nvim_buf_line_count(buf)
    pcall(vim.api.nvim_win_set_cursor, out_win, { line_count, 0 })

    if is_complete then
      vim.api.nvim_buf_set_option(buf, 'modified', true)
    end
  end

  local accumulated_output = {}
  local job_id = vim.system(cmd, {
    text = true,
    stdout = function(err, data)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if err then
          vim.notify("Error reading llm logs stdout: " .. vim.inspect(err), vim.log.levels.ERROR)
          return
        end
        if data then
          local chunks = vim.split(data, "\n", { plain = true, trimempty = false })

          if #accumulated_output > 0 and #chunks > 0 then
            accumulated_output[#accumulated_output] = accumulated_output[#accumulated_output] .. chunks[1]
            table.remove(chunks, 1)
          end

          for _, chunk in ipairs(chunks) do
            table.insert(accumulated_output, chunk)
          end

          update_buffer(accumulated_output, false)
        end
      end)
    end,
    stderr = function(err, data)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if err then
          vim.notify("Error reading llm logs stderr: " .. vim.inspect(err), vim.log.levels.ERROR)
          return
        end
        if data and data ~= "" then
          vim.notify("LLM logs stderr: " .. data, vim.log.levels.WARN)
        end
      end)
    end,
    on_exit = function(j_id, code, event)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if code ~= 0 then
          vim.notify("llm logs exited with code " .. code, vim.log.levels.WARN)
        end
        update_buffer(accumulated_output, true)
      end)
    end
  })

  if not job_id or job_id == 0 or job_id == -1 then
    vim.notify("Failed to start llm logs process. Command: " .. table.concat(cmd, " "), vim.log.levels.ERROR)
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Error: Could not start llm logs process." })
      vim.api.nvim_buf_set_option(buf, 'modified', true)
    end
  end
end

-- Command handler for the logs command
function M.handle_logs_command(args)
  local options = M.parse_args(args or "")
  M.show_logs(options)
end

return M
