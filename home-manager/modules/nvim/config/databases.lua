local path = vim.fn.expand("~/.dbs.lua")
if vim.fn.filereadable(path) == 1 then
  local ok, dbs = pcall(dofile, path)
  if ok then
    vim.g.dbs = dbs
  else
    vim.notify("Failed to load " .. path .. ": " .. dbs, vim.log.levels.WARN)
  end
end
vim.g.db_ui_use_nerd_fonts = true
