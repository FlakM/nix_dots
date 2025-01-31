-- Function to copy the GitHub URL to the clipboard
function Gbrowse_to_clip(mode)
  local start_line, end_line
  if mode == 'v' then
    -- Visual mode: get the selected lines
    start_line = vim.fn.line("'<")
    end_line = vim.fn.line("'>")
  else
    -- Normal mode: get the current line
    start_line = vim.fn.line(".")
    end_line = start_line
  end
  -- Construct the range
  local range = start_line == end_line and tostring(start_line) or start_line .. ',' .. end_line
  -- Execute GBrowse and copy the URL to the clipboard
  vim.cmd(range .. 'GBrowse!')
end

-- Normal mode mapping: copy GitHub URL of the current line
vim.api.nvim_set_keymap('n', '<leader>cg', [[:lua Gbrowse_to_clip('n')<CR>]], { noremap = true, silent = true })

-- Visual mode mapping: copy GitHub URL of the selected lines
vim.api.nvim_set_keymap('v', '<leader>cg', [[:<C-U>lua Gbrowse_to_clip('v')<CR>]], { noremap = true, silent = true })
