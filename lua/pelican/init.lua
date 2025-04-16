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

  -- Return focus to the original window
  vim.api.nvim_set_current_win(original_win)

  return buf, new_win
end

-- Function to stop a running job
function M.stop_job(bufnr)
  local pid = running_jobs[bufnr]
  if pid then
    vim.system({ 'kill', tostring(pid) })
    running_jobs[bufnr] = nil
  end
end

-- Helper function to split argument string into a list
local function split_args(args_str)
  local args = {}
  local in_quote = false
  local current = ""
  local quote_char = nil

  for i = 1, #args_str do
    local char = args_str:sub(i, i)
    if (char == '"' or char == "'") and not in_quote then
      in_quote = true
      quote_char = char
    elseif char == quote_char and in_quote then
      in_quote = false
      quote_char = nil
    elseif char == " " and not in_quote then
      if current ~= "" then
        table.insert(args, current)
        current = ""
      end
    else
      current = current .. char
    end
  end
  if current ~= "" then
    table.insert(args, current)
  end
  return args
end

-- Helper function to run llm and get output
function M.run_llm(input, args_str, bufnr, out_win)
  local cmd = { M.config.llm_path }
  local args_list = split_args(args_str or "")
  for _, arg in ipairs(args_list) do
    table.insert(cmd, arg)
  end

  local comment_line = "<!-- " .. table.concat(cmd, " ") .. " -->"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { comment_line })

  local accumulated_output = {}
  local function update_buffer(output_lines, is_complete)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      M.stop_job(bufnr)
      return
    end

    -- Set output lines starting from line 1, preserving the comment at line 0
    vim.api.nvim_buf_set_lines(bufnr, 1, -1, false, output_lines)

    -- Keep cursor at the end for streaming effect
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    pcall(vim.api.nvim_win_set_cursor, out_win, { line_count, 0 })

    if is_complete then
      vim.api.nvim_buf_set_option(bufnr, 'modified', true)
      running_jobs[bufnr] = nil
    end
  end

  local job = vim.system(cmd, {
    stdin = input,
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
    on_exit = function(code, signal)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        if code ~= 0 then
          vim.notify("llm exited with code " .. code, vim.log.levels.WARN)
        end
        update_buffer(accumulated_output, true)
      end)
    end
  })

  if not job then
    vim.notify("Failed to start llm process. Command: " .. table.concat(cmd, " "), vim.log.levels.ERROR)
    return nil
  end

  running_jobs[bufnr] = job.pid
  return job
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

-- Core function to process text
local function process_text(text, args_str)
  if not text or text == "" then
    vim.notify("No text provided to process.", vim.log.levels.WARN)
    return
  end

  local buf, out_win = create_scratch_buffer()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Requesting response from LLM..." })
  local job = M.run_llm(text, args_str, buf, out_win)

  if not job then
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Error: Could not start LLM process." })
      vim.api.nvim_buf_set_option(buf, 'modified', true)
    end
  end
end

-- Query with visual selection
function M.query_selection(args_str)
  local text, err = get_visual_selection()
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  if not text then
    vim.notify("No text selected or selection is empty.", vim.log.levels.WARN)
    return
  end
  process_text(text, args_str)
end

-- Query with a line range
function M.query_range(start_line, end_line, args_str)
  local text, err = get_range_text(start_line, end_line)
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  if not text then
    vim.notify("No text in selected range.", vim.log.levels.WARN)
    return
  end
  process_text(text, args_str)
end

-- Command handler
function M.handle_command(line1, line2, mode, args_str)
  if mode == 'v' or mode == 'V' or mode == '\22' then
    M.query_selection(args_str)
  else
    M.query_range(line1, line2, args_str)
  end
end

-- Show llm logs in a scratch buffer
function M.show_logs(args_str)
  local buf, out_win = create_scratch_buffer()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Loading LLM logs..." })

  local args_list = split_args(args_str or "")
  local cmd = { M.config.llm_path, "logs" }
  for _, arg in ipairs(args_list) do
    table.insert(cmd, arg)
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
  local job = vim.system(cmd, {
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
    on_exit = function(code, signal)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if code ~= 0 then
          vim.notify("llm logs exited with code " .. code, vim.log.levels.WARN)
        end
        update_buffer(accumulated_output, true)
      end)
    end
  })

  if not job then
    vim.notify("Failed to start llm logs process. Command: " .. table.concat(cmd, " "), vim.log.levels.ERROR)
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Error: Could not start llm logs process." })
      vim.api.nvim_buf_set_option(buf, 'modified', true)
    end
  end
end

-- Logs command handler
function M.handle_logs_command(args_str)
  M.show_logs(args_str)
end

return M
