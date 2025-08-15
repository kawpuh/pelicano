local M = {}
local last_save_times = {}
local debounce_ms = 1000 -- 1 second debounce - adjust as needed

-- Get text from visual selection (handles charwise, linewise, blockwise)
function M.get_visual_selection()
  local mode = vim.fn.visualmode()
  local lines
  local bufnr = 0  -- Current buffer

  if not mode or mode == '' then
    -- No visual selection: fallback to entire buffer
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  else
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local start_row = start_pos[2] - 1
    local start_col = start_pos[3] - 1
    local end_row = end_pos[2] - 1
    local end_col = end_pos[3]  -- Exclusive in API

    lines = {}
    if mode == 'V' then
      -- Linewise: get whole lines
      lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
    elseif mode == 'v' then
      -- Charwise: get exact text span
      lines = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {})
    elseif mode == '\22' then
      -- Blockwise: get each line's portion
      local left_col = math.min(start_pos[3], end_pos[3]) - 1
      local right_col = math.max(start_pos[3], end_pos[3])  -- Exclusive
      for row = start_row, end_row do
        local line_part = vim.api.nvim_buf_get_text(bufnr, row, left_col, row, right_col, {})[1] or ""
        table.insert(lines, line_part)
      end
    else
      return nil, "Unknown visual mode"
    end
  end

  return table.concat(lines, "\n"), nil
end

-- Function to add a name to a file
function M.add_name_to_file(name)
  -- Get the current buffer filename
  local current_file = vim.api.nvim_buf_get_name(0)

  -- Get the file extension (if any)
  local ext = ""
  local basename = current_file

  -- Find the last period in the filename (to separate extension)
  local last_dot = current_file:match(".*%.(.*)")
  if last_dot then
    ext = "." .. last_dot
    basename = current_file:sub(1, -(#ext + 1))
  end

  -- Create the new filename with the name added
  local new_file = basename .. " " .. name .. ext

  -- Save the current buffer (if modified)
  if vim.bo.modified then
    vim.cmd("silent! write")
  end

  -- Rename the file
  local success, err = os.rename(current_file, new_file)
  if not success then
    vim.notify("Failed to rename file: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return
  end

  -- Update the buffer to point to the new file
  vim.cmd("file " .. vim.fn.fnameescape(new_file))

  -- Ensure the buffer is associated with the new filename
  vim.cmd("edit " .. vim.fn.fnameescape(new_file))
end

local function save_scratch_file(args)
  local bufnr = args.buf
  local current_time = vim.loop.now()

  -- Initialize last save time for this buffer if not already done
  last_save_times[bufnr] = last_save_times[bufnr] or 0

  -- Only save if enough time has passed since the last save
  if (current_time - last_save_times[bufnr]) > debounce_ms then
    -- Only save if the buffer is modified
    if vim.bo[bufnr].modified then
      -- Save the file
      local success, err = pcall(function()
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd('silent! write')
        end)
      end)

      if success then
        last_save_times[bufnr] = current_time
      end
    end
  end
end

-- Function to set up autosave for scratch files
function M.setup_scratch_autosave()
  -- Create autocmd group for scratch files
  local augroup = vim.api.nvim_create_augroup('ScratchAutosave', { clear = true })

  -- Autocommand to detect scratch files and set up autosaving
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufNew' }, {
    group = augroup,
    callback = function(args)
      -- Get the full path of the current buffer
      local file_path = vim.api.nvim_buf_get_name(args.buf)
      local scratch_dir = vim.fn.expand('~/.local/share/nvim/scratch')

      -- Check if the file is in the scratch directory
      if file_path:find(scratch_dir, 1, true) then
        -- Setup autosave for this buffer on text changes
        vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
          group = augroup,
          buffer = args.buf,
          callback = save_scratch_file
        })

        -- Also save after a short period of idle time
        vim.api.nvim_create_autocmd('CursorHold', {
          group = augroup,
          buffer = args.buf,
          callback = save_scratch_file
        })

        -- When leaving the buffer, save it
        vim.api.nvim_create_autocmd('BufLeave', {
          group = augroup,
          buffer = args.buf,
          callback = save_scratch_file
        })

        -- Set updatetime for quicker CursorHold events
        vim.opt_local.updatetime = 1000 -- 1 second

        -- Clean up when buffer is deleted
        vim.api.nvim_create_autocmd('BufDelete', {
          group = augroup,
          buffer = args.buf,
          callback = function(args)
            last_save_times[args.buf] = nil
          end
        })
      end
    end
  })
end

-- Function to create a new scratch file
function M.create_scratch_file()
  -- Ensure the scratch directory exists
  local scratch_dir = vim.fn.expand('~/.local/share/nvim/scratch')
  if vim.fn.isdirectory(scratch_dir) == 0 then
    vim.fn.mkdir(scratch_dir, 'p')
    print("Created scratch directory: " .. scratch_dir) -- Optional feedback
  end

  -- Create a timestamp for the filename (format: YYYY-MM-DD_HH-MM-SS)
  local timestamp = os.date('%Y-%m-%d_%H-%M-%S')
  local filename = scratch_dir .. '/' .. timestamp .. '.md'

  -- Open the new scratch file
  -- Use fnameescape to handle potential special characters, though unlikely with timestamps
  vim.cmd('edit ' .. vim.fn.fnameescape(filename))
end

-- Function to open the most recent scratch file
function M.open_latest_scratch()
  local scratch_dir = vim.fn.expand('~/.local/share/nvim/scratch')

  -- Check if the directory exists
  if vim.fn.isdirectory(scratch_dir) == 0 then
    vim.notify("Scratch directory not found: " .. scratch_dir, vim.log.levels.WARN)
    return
  end

  -- Get list of files (absolute paths) in the directory
  -- globpath(dir, pattern, return_list, absolute_paths)
  local files = vim.fn.globpath(scratch_dir, '*', 1, 1)

  -- Check if the directory is empty
  if #files == 0 then
    vim.notify("Scratch directory is empty: " .. scratch_dir, vim.log.levels.INFO)
    return
  end

  local latest_mtime = -1
  local latest_file = nil

  -- Find the file with the latest modification time
  for _, file in ipairs(files) do
    -- Make sure it's a file and not a subdirectory (though '*' usually only matches files)
    if vim.fn.filereadable(file) == 1 and vim.fn.isdirectory(file) == 0 then
      local mtime = vim.fn.getftime(file)
      -- getftime returns -1 on error, ensure we have a valid time
      if mtime ~= -1 and mtime > latest_mtime then
        latest_mtime = mtime
        latest_file = file
      end
    end
  end

  -- Open the latest file if found
  if latest_file then
    -- Use fnameescape to handle potential special characters in filenames
    vim.cmd('edit ' .. vim.fn.fnameescape(latest_file))
  else
    -- This might happen if the directory only contains unreadable files or subdirs
    vim.notify("Could not determine the latest readable scratch file.", vim.log.levels.WARN)
  end
end

function M.yank_as_codeblock()
  local text_content, err = M.get_visual_selection()

  if err then
    vim.notify(err, vim.log.levels.WARN)
    return
  end

  -- Check if we actually got any text
  if not text_content or text_content == "" then
    vim.notify("No text selected or buffer is empty.", vim.log.levels.WARN)
    return
  end

  -- Get the filetype of the current buffer
  local filetype = vim.bo.filetype
  -- Use an empty string if filetype is not set or empty, so we get ``` rather than ```nil
  local lang_tag = filetype and #filetype > 0 and filetype or ""
  -- Format the text as a markdown code block
  local formatted_text = string.format("```%s\n%s\n```", lang_tag, text_content)

  -- Yank the formatted text to the default register (")
  vim.fn.setreg('"', formatted_text)

  -- Notify the user
  local lines = vim.split(text_content, "\n", { plain = true })
  local line_count = #lines
  local message = string.format("Yanked %d lines as '%s' code block", line_count,
    lang_tag ~= "" and lang_tag or "markdown")
  vim.notify(message, vim.log.levels.INFO, { title = "YankCodeblock" })
end

function M.select_within_code_block()
    -- Get current buffer
    local bufnr = vim.api.nvim_get_current_buf()
    -- Get cursor position
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local current_line = cursor_pos[1]
    -- Find start of code block (searching backwards)
    local start_line = current_line
    while start_line > 0 do
        local line = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, start_line, false)[1]
        if line and line:match("^```") then
            break
        end
        start_line = start_line - 1
    end
    -- Find end of code block (searching forwards)
    local last_line = vim.api.nvim_buf_line_count(bufnr)
    local end_line = current_line
    while end_line <= last_line do
        local line = vim.api.nvim_buf_get_lines(bufnr, end_line - 1, end_line, false)[1]
        if line and line:match("^```%s*$") then break
        end
        end_line = end_line + 1
    end
    -- If we found both delimiters, make the selection
    if start_line > 0 and end_line <= last_line then
        -- Move to start line + 1 (skip the opening delimiter)
        vim.api.nvim_win_set_cursor(0, {start_line + 1, 0})
        -- Enter normal visual mode
        vim.cmd('normal! v')
        -- Move to end line - 1 (exclude the closing delimiter)
        -- Get the content of the last line to select
        local last_content_line = vim.api.nvim_buf_get_lines(bufnr, end_line - 2, end_line - 1, false)[1]
        local last_col = 0
        if last_content_line then
            last_col = #last_content_line
        end
        -- Move to the end of the last line of content
        vim.api.nvim_win_set_cursor(0, {end_line - 1, last_col - 1})
    else
        print("No code block found")
    end
end

-- Function to extract name from filename
local function extract_name_from_filename(filename)
  -- Check if filename follows the expected format of <timestamp><maybe name>.md
  local basename = vim.fn.fnamemodify(filename, ":t:r") -- Get filename without extension and path

  -- Check if the basename starts with a timestamp pattern (YYYY-MM-DD_HH-MM-SS)
  local timestamp_pattern = "^%d%d%d%d%-%d%d%-%d%d_%d%d%-%d%d%-%d%d"

  -- If there's a timestamp, check if there's additional text after it
  if basename:match(timestamp_pattern) then
    local timestamp_end = basename:match(timestamp_pattern .. "()")

    -- If there's text after the timestamp, extract it (skip any spaces)
    if timestamp_end and timestamp_end <= #basename then
      local name = basename:sub(timestamp_end):match("^ +(.*)")
      return name
    end
  end

  return nil
end

-- Function to create a scratch branch from current buffer
function M.scratch_branch()
  -- Get current buffer content
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local current_file = vim.api.nvim_buf_get_name(0)

  -- Create a new scratch file
  M.create_scratch_file()

  -- Get the new buffer
  local new_bufnr = vim.api.nvim_get_current_buf()

  -- Set the content from the original buffer
  vim.api.nvim_buf_set_lines(new_bufnr, 0, -1, false, lines)

  -- Check if the original file follows the timestamp format and has a name
  local name = extract_name_from_filename(current_file)

  -- If a name is found, call ScratchAddName
  if name then
    M.add_name_to_file(name)
  end
end

return M
