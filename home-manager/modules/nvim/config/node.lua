local lspconfig = require('lspconfig')
local null_ls = require('null-ls')

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
    filetypes = { "javascript" },
    sources = {
        formatting.prettier,
    },
    on_attach = function(client)
        if client.supports_method("textDocument/formatting") then
            vim.api.nvim_clear_autocmds({ group = augroup })
            vim.api.nvim_create_autocmd("BufWritePre", {
                group = augroup,
                pattern = "*.js",
                callback = function(args)
                    vim.lsp.buf.format({ bufnr = args.buf })
                end,
            })
        end
    end,
})
