local gopls_path = vim.fn.exepath("gopls")
if gopls_path ~= "" then
  vim.lsp.config("gopls", {
    cmd = { "lspmux", "client", "--server-path", gopls_path },
    settings = {
      gopls = {
        completeUnimported = true,
        gofumpt = true,
        staticcheck = true,
        usePlaceholders = true,
      },
    },
  })
  vim.lsp.enable("gopls")
end

vim.lsp.enable("terraformls")
