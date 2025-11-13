-- Function to copy the GitHub URL to the clipboard as Markdown
function Gbrowse_to_clip(use_visual_marks)
  -- Ensure GBrowse exists
  if vim.fn.exists(':GBrowse') == 0 then
    vim.notify('GBrowse command not found', vim.log.levels.ERROR, { title = 'Git link' })
    return
  end

  local start_line, end_line

  if use_visual_marks then
    start_line = tonumber(vim.fn.line("'<"))
    end_line = tonumber(vim.fn.line("'>"))
  else
    local current_line = tonumber(vim.fn.line("."))
    start_line = current_line
    end_line = current_line
  end

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local range = start_line == end_line
    and tostring(start_line)
    or (start_line .. ',' .. end_line)

  -- Execute GBrowse and copy the URL to the clipboard
  local ok, err = pcall(vim.cmd, ('silent %sGBrowse!'):format(range))
  if not ok then
    vim.notify('GBrowse failed: ' .. err, vim.log.levels.ERROR, { title = 'Git link' })
    return
  end

  vim.defer_fn(function()
    local url = vim.fn.getreg('+')
    if url == '' then
      url = vim.fn.getreg('"')
    end
    if url == '' then
      vim.notify('⚠️ Git link not available', vim.log.levels.WARN, { title = 'Git link' })
      return
    end

    local base, fragment = url:match('([^#]+)(#.*)?$')
    base = base or url
    local path_without_query = base:match('([^?]+)') or base
    local filename = path_without_query:match('([^/]+)$') or path_without_query

    local label
    if fragment and fragment:match('#L') then
      label = filename .. ':' .. fragment:sub(2)
    else
      label = filename .. (fragment or '')
    end

    local markdown = string.format('[%s](%s)', label, url)

    vim.fn.setreg('+', markdown)
    vim.fn.setreg('"', markdown)
    vim.notify('🔗 Git ref copied ' .. label, vim.log.levels.INFO, { title = 'Git link' })
  end, 50)

end

-- Normal mode mapping
vim.keymap.set('n', '<leader>cg', Gbrowse_to_clip, {
  noremap = true,
  silent = true,
  desc = 'Copy GitHub link as Markdown',
})

-- Visual mode mapping - need to escape visual mode first to update marks
vim.keymap.set('v', '<leader>cg', function()
  local start_line = vim.fn.line('v')
  local end_line = vim.fn.line('.')

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)

  vim.fn.setpos("'<", {0, math.min(start_line, end_line), 1, 0})
  vim.fn.setpos("'>", {0, math.max(start_line, end_line), 999, 0})

  vim.schedule(function()
    Gbrowse_to_clip(true)
  end)
end, {
  noremap = true,
  silent = true,
  desc = 'Copy GitHub link as Markdown',
})
