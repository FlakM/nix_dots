require("obsidian").setup({
    workspaces = {
        {
            name = "work",
            path = "~/programming/flakm/obsidian/work"
        }
    },

    notes_subdir = "daily",
    mappings = {
       -- Overrides the 'gf' mapping to work on markdown/wiki links within your vault.
       ["gd"] = {
         action = function()
           return require("obsidian").util.gf_passthrough()
         end,
         opts = { noremap = false, expr = true, buffer = true },
       },
       -- Toggle check-boxes.
       ["<leader>ch"] = {
         action = function()
           return require("obsidian").util.toggle_checkbox()
         end,
         opts = { buffer = true },
       },
       -- Smart action depending on context, either follow link or toggle checkbox.
       ["<cr>"] = {
         action = function()
           return require("obsidian").util.smart_action()
         end,
         opts = { buffer = true, expr = true },
        }
    }
})

-- set conceallevel to 2
vim.cmd("set conceallevel=2")
