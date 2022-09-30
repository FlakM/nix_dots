
lua << EOF

local lspconfig          = require 'lspconfig'

lspconfig.gopls.setup {
  on_attach = on_attach,
}

-- https://github.com/golang/tools/blob/1f10767725e2be1265bef144f774dc1b59ead6dd/gopls/doc/vim.md#imports
function OrgImports(wait_ms)
  local params = vim.lsp.util.make_range_params()
  params.context = {only = {"source.organizeImports"}}
  local result = vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, wait_ms)
  for _, res in pairs(result or {}) do
    for _, r in pairs(res.result or {}) do
      if r.edit then
        vim.lsp.util.apply_workspace_edit(r.edit, "UTF-8")
      else
        vim.lsp.buf.execute_command(r.command)
      end
    end
  end
end

vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = {'*.go'},
  callback = function()
      vim.lsp.buf.formatting_sync()
      OrgImports(1000)
  end,
  group = vim.api.nvim_create_augroup("lsp_document_format", {clear = true}),
})

EOF
