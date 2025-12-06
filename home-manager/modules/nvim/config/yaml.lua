vim.lsp.config('yamlls', {
--   -- other configuration for setup {}
--  settings = {
--    yaml = {
--      -- ... -- other settings. note this overrides the lspconfig defaults.
--      schemas = {
--        ["https://json.schemastore.org/github-workflow.json"] = "/.github/workflows/*",
--        --["../path/relative/to/file.yml"] = "/.github/workflows/*",
--        --["/path/from/root/of/project"] = "/.github/workflows/*",
--      },
--    },
--  }
})

vim.lsp.enable('yamlls')
