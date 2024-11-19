-- Set up the nvim-metals configuration for Scala, SBT, and Java file types
local metals_config = require("metals").bare_config()

metals_config.settings = { 
    metalsBinaryPath = metals_path,
    showInferredType = true,
    showImplicitArguments = true,
}

-- Define the on_attach function for LSP configuration
metals_config.on_attach = function(client, bufnr)
  -- Customize on_attach behavior here
end

-- Create an autogroup for nvim-metals
local nvim_metals_group = vim.api.nvim_create_augroup("nvim-metals", { clear = true })

-- Set up an autocmd for the FileType event to initialize or attach nvim-metals
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "scala", "sbt", "java" },
  callback = function()
    require("metals").initialize_or_attach(metals_config)
  end,
  group = nvim_metals_group,
})
