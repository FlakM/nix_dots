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
        }
    },

    notes_subdir = "daily",
    mappings = {
        -- Show backlinks for the current note. Mnemonic: go to references
        ["gr"] = {
          action = function()
              vim.api.nvim_command("ObsidianBacklinks")
          end,
          opts = { buffer = true },
        },
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
     },
    }
})


map("n", "<leader>D", [[<cmd>ObsidianDailies<CR>]])
map("n", "<leader>1", [[<cmd>ObsidianYesterday<CR>]])
map("n", "<leader>2", [[<cmd>ObsidianToday<CR>]])
map("n", "<leader>3", [[<cmd>ObsidianTomorrow<CR>]])

-- set conceallevel to 2
vim.cmd("set conceallevel=2")
