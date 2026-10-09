local eslint_on_attach = vim.lsp.config.eslint.on_attach
vim.lsp.config("eslint", {
  settings = {
    format = false,
    workingDirectory = { mode = "auto" },
  },
  on_attach = function(client, bufnr)
    if eslint_on_attach then
      eslint_on_attach(client, bufnr)
    end
    local group = vim.api.nvim_create_augroup("eslint_fix_all", { clear = false })
    vim.api.nvim_clear_autocmds({ group = group, buffer = bufnr })
    vim.api.nvim_create_autocmd("BufWritePre", {
      group = group,
      buffer = bufnr,
      command = "EslintFixAll",
    })
  end,
})
vim.lsp.enable("eslint")

local vtsls_path = vim.fn.exepath("vtsls")
if vtsls_path ~= "" then
  vim.lsp.config("vtsls", {
    cmd = { "lspmux", "client", "--server-path", vtsls_path, "--", "--stdio" },
    settings = {
      vtsls = {
        autoUseWorkspaceTsdk = true,
      },
      typescript = {
        inlayHints = {
          parameterNames = { enabled = "literals" },
          parameterTypes = { enabled = true },
          variableTypes = { enabled = true },
          propertyDeclarationTypes = { enabled = true },
          functionLikeReturnTypes = { enabled = true },
          enumMemberValues = { enabled = true },
        },
      },
    },
  })
  vim.lsp.enable("vtsls")
end
