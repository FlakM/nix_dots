-- Function to copy the GitHub URL to the clipboard
local function in_visual(m)
  return m == 'v' or m == 'V' or m == '\22'
end

function Gbrowse_to_clip(mode)
  local start_line, end_line
  if in_visual(mode) then
    start_line = tonumber(vim.fn.line("'<")) or tonumber(vim.fn.line(".")) or 1
    end_line = tonumber(vim.fn.line("'>")) or start_line
    vim.cmd("normal! \\<Esc>")
  else
    start_line = tonumber(vim.fn.line(".")) or 1
    end_line = start_line
  end
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local range = start_line == end_line and tostring(start_line) or start_line .. ',' .. end_line
  -- Execute GBrowse and copy the URL to the clipboard
  vim.cmd('silent ' .. range .. 'GBrowse!')

  local url = vim.fn.getreg("+") or ""
  if url == "" then
    vim.notify("⚠️ Git link not available", vim.log.levels.WARN, { title = "Git link" })
    return
  end

  local base, fragment = url:match("([^#]+)(#.*)?$")
  base = base or url
  local path_without_query = (base:match("([^?]+)")) or base
  local filename = path_without_query:match("([^/]+)$") or path_without_query
  local label = filename .. (fragment or "")
  local markdown = string.format("[%s](%s)", label, url)

  vim.fn.setreg("+", markdown)
  vim.notify("🔗 Git ref copied " .. label, vim.log.levels.INFO, { title = "Git link" })
end

-- Normal mode mapping: copy GitHub URL of the current line
vim.api.nvim_set_keymap('n', '<leader>cg', [[:lua Gbrowse_to_clip('n')<CR>]], { noremap = true, silent = true })

-- Visual mode mapping: copy GitHub URL of the selected lines
vim.api.nvim_set_keymap('v', '<leader>cg', [[:<C-U>lua Gbrowse_to_clip('v')<CR>]], { noremap = true, silent = true })
