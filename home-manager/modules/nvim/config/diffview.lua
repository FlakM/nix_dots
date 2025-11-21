local ok, diffview = pcall(require, "diffview")
if not ok then
    return
end

diffview.setup({
    enhanced_diff_hl = true,
    view = {
        default = {
            layout = "diff2_horizontal",
        },
        merge_tool = {
            layout = "diff3_mixed",
            disable_diagnostics = true,
        },
    },
    file_panel = {
        listing_style = "tree",
        win_config = {
            position = "left",
            width = 35,
        },
    },
    hooks = {
        diff_buf_read = function()
            vim.opt_local.wrap = false
        end,
    },
})

local map = vim.keymap.set
local opts = { noremap = true, silent = true }

map("n", "<leader>do", "<cmd>DiffviewOpen<CR>", vim.tbl_extend("force", opts, { desc = "Diffview open" }))
map("n", "<leader>dc", "<cmd>DiffviewClose<CR>", vim.tbl_extend("force", opts, { desc = "Diffview close" }))
map("n", "<leader>df", "<cmd>DiffviewFileHistory %<CR>", vim.tbl_extend("force", opts, { desc = "Diffview file history" }))
map("n", "<leader>dF", "<cmd>DiffviewFileHistory<CR>", vim.tbl_extend("force", opts, { desc = "Diffview repo history" }))
