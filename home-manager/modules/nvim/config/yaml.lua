local schemastore = require("schemastore")

vim.lsp.config("jsonls", {
  settings = {
    json = {
      schemas = schemastore.json.schemas(),
      validate = { enable = true },
    },
  },
})
vim.lsp.enable("jsonls")

vim.lsp.config("yamlls", {
  filetypes = { "yaml", "yaml.docker-compose", "yaml.gitlab", "yaml.helm-values", "yaml.ghaction" },
  settings = {
    yaml = {
      schemaStore = {
        enable = false,
        url = "",
      },
      schemas = schemastore.yaml.schemas(),
      validate = true,
    },
  },
})
vim.lsp.enable("yamlls")

vim.lsp.enable("clangd")
