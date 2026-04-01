vim.lsp.config('html', {
  filetypes = { 'html', 'templ' },
  settings = {
    html = {
      format = { enable = true },
      hover = { documentation = true, references = true },
    },
  },
})
vim.lsp.enable('html')

vim.lsp.config('cssls', {
  filetypes = { 'css', 'scss', 'less' },
})
vim.lsp.enable('cssls')
