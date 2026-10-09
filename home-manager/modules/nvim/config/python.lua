local basedpyright_path = vim.fn.exepath("basedpyright-langserver")
if basedpyright_path ~= "" then
  vim.lsp.config("basedpyright", {
    cmd = { "lspmux", "client", "--server-path", basedpyright_path, "--", "--stdio" },
    settings = {
      basedpyright = {
        analysis = {
          diagnosticMode = "openFilesOnly",
          typeCheckingMode = "standard",
        },
      },
    },
  })
  vim.lsp.enable("basedpyright")
end

vim.lsp.enable("ruff")
