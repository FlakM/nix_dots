
require'lspconfig'.protols.setup{}

-- Format on save
vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = "*.proto", -- Replace with the appropriate file type for Protobuf
    callback = function()
        vim.lsp.buf.format({ async = false }) -- Use async=false for synchronous formatting
    end,
})
