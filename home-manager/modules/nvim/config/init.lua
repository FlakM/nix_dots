local api = vim.api
local cmd = vim.cmd

local function map(mode, lhs, rhs, opts)
    local options = { noremap = true }
    if opts then
        options = vim.tbl_extend("force", options, opts)
    end
    api.nvim_set_keymap(mode, lhs, rhs, options)
end

-- open in a dark mode
vim.cmd 'colorscheme default'
vim.g.edge_style = "default"
vim.g.edge_transparent_background = 2

vim.g.mapleader = " "
vim.cmd 'colorscheme edge'

-- for showing lsp init process status
require("fidget").setup {
    -- options
}

-- for showing git blame
require('gitblame').setup {
    --Note how the `gitblame_` prefix is omitted in `setup`
    enabled = false,
}


--
-- nvim-tree section
--
require 'nvim-tree'.setup {
    view = {
        width = 50,
    },
    hijack_cursor = true,
    update_focused_file = {
        enable = true,
    },
}


map("n", "<C-n>", [[<cmd>NvimTreeToggle<CR>]])
map("n", "<leader>r", [[<cmd>NvimTreeRefresh<CR>]])

-- this is alt + 1 in my keyboard on mac
-- you can test it by running cat and pressing alt + 1
map("n", "Ń", [[<cmd>NvimTreeFindFile<CR>]])
-- this is on dell
map("n", "≠", [[<cmd>NvimTreeFindFile<CR>]])

map("n", "<leader>n", [[<cmd>NvimTreeFindFile<CR>]])


--
-- telescope section
--
-- Find files using Telescope command-line sugar.
map("n", "<leader>ff", [[<cmd>Telescope find_files<CR>]])
--map("n", "<leader>fg", [[<cmd>Telescope live_grep<CR>]])
map("n", "<leader>fg", ":lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>")


map("n", "<leader>fb", [[<cmd>Telescope buffers<CR>]])
map("n", "<leader>fh", [[<cmd>Telescope help_tags<CR>]])


-- Replace visually selected text with contents of register without yanking
-- https://superuser.com/questions/321547/how-do-i-replace-paste-yanked-text-in-vim-without-yanking-the-deleted-lines
map("v", "<leader>p", [["_dP]])


if vim.fn.filereadable(vim.fn.expand("~/.config/current-color_scheme")) == 1 then
    local file = io.open(vim.fn.expand("~/.config/current-color_scheme"), "r")
    local theme = file:read()
    if theme == "prefer-light" then
        vim.g.background = "light"
        vim.cmd("set background=light")
        -- set visual selection color to pink
        vim.api.nvim_set_hl(0, "Visual", { bg = "#ffc0cb", fg = "NONE" })
    else
        vim.g.background = "dark"
        vim.cmd("set background=dark")
    end
    file:close()
end


function switch_theme()
    -- toggle background if dark or not set
    if vim.g.background == "dark" or vim.g.background == nil then
        vim.g.background = "light"
        vim.cmd("set background=light")
        -- set visual selection color to pink
        vim.api.nvim_set_hl(0, "Visual", { bg = "#ffc0cb", fg = "NONE" })
    else
        vim.g.background = "dark"
        vim.cmd("set background=dark")
    end
end

-- Jump to start and end of line using the home row keys
vim.keymap.set({ "n", "v", "o" }, "L", "g$", { noremap = true, silent = true })
vim.keymap.set({ "n", "v", "o" }, "H", "g^", { noremap = true, silent = true })
