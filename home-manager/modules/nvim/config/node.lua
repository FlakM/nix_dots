local lspconfig = require('lspconfig')
local null_ls = require('null-ls')

-- Function to handle on_attach events
local on_attach = function(client, bufnr)
    -- Disable formatting by tsserver to avoid conflicts with prettier
    client.server_capabilities.documentFormattingProvider = false
end

-- Setup TypeScript Language Server
lspconfig.ts_ls.setup {
    on_attach = on_attach,
}


local formatting = require("null-ls").builtins.formatting
local augroup = vim.api.nvim_create_augroup("LspFormatting", {})

null_ls.setup({
    debug = true,
    filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
    sources = {
        formatting.prettier,
    },
    on_attach = function(client, bufnr)
        if client.supports_method("textDocument/formatting") then
            vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
            vim.api.nvim_create_autocmd("BufWritePre", {
                group = augroup,
                buffer = bufnr,
                callback = function()
                    vim.lsp.buf.format({ bufnr = bufnr })
                end,
            })
        end
    end,
})
