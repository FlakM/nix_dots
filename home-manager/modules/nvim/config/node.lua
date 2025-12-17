local util = require('lspconfig.util')

-- Only setup ESLint if the project root has a .eslintrc.json file
local eslint_root = util.root_pattern(".eslintrc.json")
if eslint_root(vim.fn.getcwd()) then
  vim.lsp.config('eslint', {
    root_dir = eslint_root,
    settings = {
      format = true,
    },
    on_attach = function(client, bufnr)
      vim.api.nvim_create_autocmd("BufWritePre", {
        buffer = bufnr,
        command = "EslintFixAll",
      })
    end,
  })
  vim.lsp.enable('eslint')
end

-- Setup TypeScript Language Server via lspmux
local ts_ls_path = vim.fn.exepath("typescript-language-server")
if ts_ls_path ~= "" then
  vim.lsp.config('ts_ls', {
    cmd = { "lspmux", "client", "--server-path", ts_ls_path, "--", "--stdio" },
    settings = {
      completions = {
        completeFunctionCalls = true,
      },
    },
  })
end
vim.lsp.enable('ts_ls')

-- Only setup Prettier formatting if the project root has a .prettierrc file
local prettier_root = util.root_pattern(".prettierrc")
if prettier_root(vim.fn.getcwd()) then
  local null_ls = require('null-ls')
  local formatting = null_ls.builtins.formatting
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
end
