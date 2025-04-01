-- Command to create and open a scratch file with timestamp
vim.api.nvim_create_user_command('Scratch', function()
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
end, {})

-- Command to open the most recently modified scratch file
vim.api.nvim_create_user_command('OpenLatestScratch', function()
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
end, {})

-- Autosave functionality for scratch files
local function setup_scratch_autosave()
  -- Create autocmd group for scratch files
  local augroup = vim.api.nvim_create_augroup('ScratchAutosave', { clear = true })

  -- Track the last save time for debouncing (per buffer)
  local last_save_times = {}
  local debounce_ms = 1000 -- 1 second debounce - adjust as needed

  -- Save the current scratch file with debouncing
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

  -- Autocommand to detect scratch files and set up autosaving
  vim.api.nvim_create_autocmd({'BufEnter', 'BufNew'}, {
    group = augroup,
    callback = function(args)
      -- Get the full path of the current buffer
      local file_path = vim.api.nvim_buf_get_name(args.buf)
      local scratch_dir = vim.fn.expand('~/.local/share/nvim/scratch')

      -- Check if the file is in the scratch directory
      if file_path:find(scratch_dir, 1, true) then
        -- Setup autosave for this buffer on text changes
        vim.api.nvim_create_autocmd({'TextChanged', 'TextChangedI'}, {
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

setup_scratch_autosave()
