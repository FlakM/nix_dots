require("which-key").setup({})
require("trouble").setup({})
require("octo").setup({
  picker = "telescope",
  enable_builtin = true,
})

local map = vim.keymap.set
map("n", "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", { desc = "Workspace diagnostics" })
map("n", "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", { desc = "Buffer diagnostics" })
map("n", "<leader>xs", "<cmd>Trouble symbols toggle focus=false<cr>", { desc = "Document symbols" })
map("n", "<leader>xl", "<cmd>Trouble lsp toggle focus=false win.position=right<cr>", { desc = "LSP locations" })
map("n", "<leader>xq", "<cmd>Trouble qflist toggle<cr>", { desc = "Quickfix list" })
map("n", "<leader>op", "<cmd>Octo pr list<cr>", { desc = "GitHub pull requests" })
map("n", "<leader>oi", "<cmd>Octo issue list<cr>", { desc = "GitHub issues" })
map("n", "<leader>on", "<cmd>Octo notification list<cr>", { desc = "GitHub notifications" })
