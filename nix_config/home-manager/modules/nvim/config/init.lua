local api = vim.api
local cmd = vim.cmd

local function map(mode, lhs, rhs, opts)
  local options = { noremap = true }
  if opts then
    options = vim.tbl_extend("force", options, opts)
  end
  api.nvim_set_keymap(mode, lhs, rhs, options)
end

require('material').setup({
    high_visibility = {
        lighter = true, -- Enable higher contrast text for lighter style
        darker = false -- Enable higher contrast text for darker style
    },
})


--Lua:
vim.cmd 'colorscheme material'
vim.g.material_style = "lighter"

vim.g.mapleader = " "


--
-- nvim-tree section
--
require'nvim-tree'.setup {
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
map("n", "<leader>fg", [[<cmd>Telescope live_grep<CR>]])
map("n", "<leader>fb", [[<cmd>Telescope buffers<CR>]])
map("n", "<leader>fh", [[<cmd>Telescope help_tags<CR>]])


-- Replace visually selected text with contents of register without yanking 
-- https://superuser.com/questions/321547/how-do-i-replace-paste-yanked-text-in-vim-without-yanking-the-deleted-lines
map("v", "<leader>p", [["_dP]])


function switch_theme()
  if vim.g.material_style == "lighter" then
    vim.g.material_style = "oceanic"
    vim.cmd('set background=dark')
  else
    vim.g.material_style = "lighter"
    vim.cmd('set background=light')
  end
  cmd('colorscheme material')
end


map("n", "<leader>l", [[<cmd>lua switch_theme()<CR>]])
