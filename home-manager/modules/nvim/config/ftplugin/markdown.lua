vim.opt.wrap = true                          -- Enable line wrapping
vim.opt.linebreak = true                     -- Wrap lines at word boundaries
vim.opt.breakindent = true                   -- Enable break indent (optional)
vim.opt.breakindentopt = "shift:2"           -- Set break indent options (optional)
vim.opt.showbreak = "↪ "                     -- Visual indicator for wrapped lines (optional)
vim.opt.formatoptions:remove("t")            -- Prevent automatic text reformatting
