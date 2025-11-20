local api = vim.api
local cmd = vim.cmd
local map = vim.keymap.set
local builtin = require('telescope.builtin')

local lsp_lines = require("lsp_lines")
lsp_lines.setup()

vim.diagnostic.config({
    virtual_text = false,
    virtual_lines = true,
    signs = {
        priority = 20,
    },
    underline = true,
    severity_sort = true,
})

vim.api.nvim_set_hl(0, "DiagnosticVirtualTextError", { fg = "#ff4d4d", bg = "NONE" })
vim.api.nvim_set_hl(0, "DiagnosticSignError", { fg = "#ff4d4d", bg = "NONE" })
vim.api.nvim_set_hl(0, "DiagnosticSignWarn", { fg = "#fabd2f", bg = "NONE" })
vim.api.nvim_set_hl(0, "DiagnosticSignInfo", { fg = "#83a598", bg = "NONE" })
vim.api.nvim_set_hl(0, "DiagnosticSignHint", { fg = "#b8bb26", bg = "NONE" })

local diagnostic_signs = { Error = "●", Warn = "●", Hint = "●", Info = "●" }
for type, icon in pairs(diagnostic_signs) do
    local hl = "DiagnosticSign" .. type
    vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
end

--LSP mappings
-- go to definition
map("n", "gd", function()
    vim.lsp.buf.definition()
end)

map("n", "gtd", function()
    vim.lsp.buf.type_definition()
end)

-- print item's docs
map("n", "K", function()
    vim.lsp.buf.hover()
end)

-- go to implementation
map("n", "gi", function()
    vim.lsp.buf.implementation()
    --builtin.lsp_implementations()
end)

-- show references using telescope
map("n", "gr", function()
    --vim.lsp.buf.references()
    builtin.lsp_references()
end)

-- show document symbols using telescope
map("n", "gds", function()
    --vim.lsp.buf.document_symbol()
    builtin.lsp_document_symbols()
end)

-- show workspace symbols using telescope
map("n", "gws", function()
    --vim.lsp.buf.workspace_symbol()
    builtin.lsp_workspace_symbols()
end)

map("n", "<leader>cl", function()
    vim.lsp.codelens.run()
end)

map("n", "<leader>sh", function()
    vim.lsp.buf.signature_help()
end)

map("n", "<leader>FF", function()
    vim.lsp.buf.format { async = true }
end)


map("n", "<leader>rn", function()
    vim.lsp.buf.rename()
end)


map("n", "<leader>ca", function()
    vim.lsp.buf.code_action()
end)

-- all workspace diagnostics
map("n", "<leader>aa", function()
    vim.diagnostic.setqflist()
end)

-- all workspace errors
map("n", "<leader>ae", function()
    vim.diagnostic.setqflist({ severity = "ERROR" })
end)

-- all workspace warnings
map("n", "<leader>aw", function()
    vim.diagnostic.setqflist({ severity = "WARN" })
end)

-- buffer diagnostics only
map("n", "<leader>d", function()
    vim.diagnostic.setloclist()
end)

map("n", "[c", function()
    vim.diagnostic.goto_prev({ wrap = false })
end)

map("n", "]c", function()
    vim.diagnostic.goto_next({ wrap = false })
end)

-- Toggle inlay hints
map("n", "<leader>l", function()
    local enabled = vim.lsp.inlay_hint.is_enabled()
    vim.lsp.inlay_hint.enable(not enabled)
    lsp_lines.toggle()
end, { desc = "Toggle inlay hints and diagnostics" })

-- Example mappings for usage with nvim-dap. If you don't use that, you can skip these



-- Toggle breakpoint
map("n", "<leader>dt", function()
    require("dap").toggle_breakpoint()
end)

-- Continue execution
map("n", "<leader>dc", function()
    require("dap").continue()
end)

-- Step over
map("n", "<leader>dso", function()
    require("dap").step_over()
end)

-- Step into
map("n", "<leader>dsi", function()
    require("dap").step_into()
end)

-- Step out
map("n", "<leader>dsO", function()
    require("dap").step_out()
end)

-- Run last configuration
map("n", "<leader>dl", function()
    require("dap").run_last()
end)

-- Open dapui
map("n", "<leader>duo", function()
    require("dapui").open()
end)

-- Close dapui
map("n", "<leader>duc", function()
    require("dapui").close()
end)


require 'lspconfig'.nil_ls.setup {
    autostart = true,
    settings = {
        ['nil'] = {
            testSetting = 42,
            formatting = {
                command = { "nixpkgs-fmt" },
            },
        },
    },

}

-- completion related settings
-- This is similiar to what I use
local cmp = require("cmp")
cmp.setup({
    sources = {
        { name = 'path',                   keyword_length = 3 }, -- file paths
        { name = 'nvim_lsp', },                                  -- from language server
        { name = 'nvim_lsp_signature_help' },                    -- display function signatures with current parameter emphasized
        { name = 'nvim_lua',               keyword_length = 2 }, -- complete neovim's Lua runtime API such vim.lsp.*
        { name = 'buffer',                 keyword_length = 2 }, -- source current buffer
        { name = 'vsnip',                  keyword_length = 2 }, -- nvim-cmp source for vim-vsnip
        { name = 'vim-dadbod-completion' },                      -- source for vim-dadbod
    },
    snippet = {
        expand = function(args)
            -- Comes from vsnip
            vim.fn["vsnip#anonymous"](args.body)
        end,
    },
    mapping = cmp.mapping.preset.insert({
        ['<C-p>'] = cmp.mapping.select_prev_item(),
        ['<C-n>'] = cmp.mapping.select_next_item(),
        -- Add tab support
        ['<S-Tab>'] = cmp.mapping.select_prev_item(),
        ['<Tab>'] = cmp.mapping.select_next_item(),
        ['<C-S-f>'] = cmp.mapping.scroll_docs(-4),
        ['<C-f>'] = cmp.mapping.scroll_docs(4),
        ['<C-Space>'] = cmp.mapping.complete(),
        ['<C-e>'] = cmp.mapping.close(),
        ['<CR>'] = cmp.mapping.confirm({
            behavior = cmp.ConfirmBehavior.Insert,
            select = true,
        })
    }),
})
