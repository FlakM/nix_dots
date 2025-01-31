require'marks'.setup {}

vim.api.nvim_set_keymap('n', '<leader>fm', [[<cmd>lua require('telescope.builtin').marks({ mark_type = "local" })<CR>]], { noremap = true, silent = true })
