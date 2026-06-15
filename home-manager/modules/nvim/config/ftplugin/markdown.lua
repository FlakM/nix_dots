vim.opt_local.wrap = true                    -- Soft wrap long lines
vim.opt_local.linebreak = true               -- Wrap at word boundaries if wrap is toggled on
vim.opt_local.breakindent = true             -- Enable break indent if wrap is toggled on
vim.opt_local.breakindentopt = "shift:2"     -- Break indent shift
vim.opt_local.showbreak = "↪ "              -- Visual indicator for wrapped lines
vim.opt_local.formatoptions:remove("t")      -- Prevent automatic text reformatting
