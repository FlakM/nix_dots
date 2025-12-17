local api = vim.api

local function extend_with_on_attach(opts)
  opts = opts or {}
  if type(_G.on_attach) == "function" then
    opts.on_attach = _G.on_attach
  end
  return opts
end

local gopls_path = vim.fn.exepath("gopls")
if gopls_path ~= "" then
  vim.lsp.config('gopls', extend_with_on_attach({
    cmd = { "lspmux", "client", "--server-path", gopls_path },
  }))
end
vim.lsp.enable('gopls')

vim.lsp.config('terraform_lsp', extend_with_on_attach({}))
vim.lsp.enable('terraform_lsp')

local function org_imports(wait_ms)
  local params = vim.lsp.util.make_range_params()
  params.context = { only = { "source.organizeImports" } }
  local result = vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, wait_ms)
  for _, res in pairs(result or {}) do
    for _, r in pairs(res.result or {}) do
      if r.edit then
        vim.lsp.util.apply_workspace_edit(r.edit, "UTF-8")
      elseif r.command then
        vim.lsp.buf.execute_command(r.command)
      end
    end
  end
end

local function format_buffer()
  if vim.lsp.buf.format then
    vim.lsp.buf.format({ async = false })
  else
    vim.lsp.buf.formatting_sync()
  end
end

local go_format_group = api.nvim_create_augroup("GoFormatOnSave", { clear = true })

api.nvim_create_autocmd("BufWritePre", {
  group = go_format_group,
  pattern = "*.go",
  callback = function()
    format_buffer()
    org_imports(1000)
  end,
})
