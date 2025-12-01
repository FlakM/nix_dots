local api = vim.api
local cmd = vim.cmd

local function map(mode, lhs, rhs, opts)
  local options = { noremap = true }
  if opts then
    options = vim.tbl_extend("force", options, opts)
  end
  api.nvim_set_keymap(mode, lhs, rhs, options)
end

require("obsidian").setup({
    workspaces = {
        {
            name = "work",
            path = "~/programming/flakm/obsidian/work"
        },
        {
            name = "house",
            path = "~/programming/flakm/obsidian/house/house"
        }
    },

    notes_subdir = "daily",
    legacy_commands = false,
})

-- Set up keymaps manually (mappings option is deprecated)
vim.api.nvim_create_autocmd("FileType", {
    pattern = "markdown",
    callback = function()
        local bufnr = vim.api.nvim_get_current_buf()

        -- Show backlinks for the current note. Mnemonic: go to references
        vim.keymap.set("n", "gr", function()
            vim.cmd("Obsidian backlinks")
        end, { buffer = bufnr, desc = "Obsidian backlinks" })

        -- Overrides the 'gf' mapping to work on markdown/wiki links within your vault.
        vim.keymap.set("n", "gd", function()
            return require("obsidian").util.gf_passthrough()
        end, { buffer = bufnr, noremap = false, expr = true, desc = "Follow link" })

        -- Toggle check-boxes.
        vim.keymap.set("n", "<leader>ch", function()
            return require("obsidian").util.toggle_checkbox()
        end, { buffer = bufnr, desc = "Toggle checkbox" })

        -- Smart action depending on context, either follow link or toggle checkbox.
        vim.keymap.set("n", "<cr>", function()
            return require("obsidian").util.smart_action()
        end, { buffer = bufnr, expr = true, desc = "Smart action" })
    end,
})


map("n", "<leader>D", [[<cmd>Obsidian dailies<CR>]])
map("n", "<leader>1", [[<cmd>Obsidian yesterday<CR>]])
map("n", "<leader>2", [[<cmd>Obsidian today<CR>]])
map("n", "<leader>3", [[<cmd>Obsidian tomorrow<CR>]])

-- set conceallevel to 2
vim.cmd("set conceallevel=2")

-- Obsidian buffers are opened by background jobs, so disable swapfiles for them
-- to avoid E325 warnings when the plugin re-edits an already-open note.
local obsidian_paths = {
    vim.fn.expand("~/programming/flakm/obsidian/work") .. "/**",
    vim.fn.expand("~/programming/flakm/obsidian/house/house") .. "/**",
}
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = obsidian_paths,
    callback = function()
        vim.opt_local.swapfile = false
    end,
})
