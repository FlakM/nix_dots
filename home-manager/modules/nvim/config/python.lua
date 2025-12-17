-- Setup Pyright via lspmux
local pyright_path = vim.fn.exepath("pyright-langserver")
if pyright_path ~= "" then
  vim.lsp.config('pyright', {
    cmd = { "lspmux", "client", "--server-path", pyright_path, "--", "--stdio" },
  })
end
vim.lsp.enable('pyright')
