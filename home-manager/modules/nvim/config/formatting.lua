local conform = require("conform")

conform.setup({
  formatters_by_ft = {
    bash = { "shfmt" },
    c = { "clang_format" },
    cpp = { "clang_format" },
    css = { "prettier" },
    go = { "goimports", "gofmt" },
    html = { "prettier" },
    javascript = { "prettier" },
    javascriptreact = { "prettier" },
    json = { "prettier" },
    jsonc = { "prettier" },
    lua = { "stylua" },
    markdown = { "prettier" },
    nix = { "nixfmt" },
    proto = { "buf" },
    python = { "ruff_format" },
    rust = { "rustfmt" },
    scss = { "prettier" },
    sh = { "shfmt" },
    terraform = { "terraform_fmt" },
    typescript = { "prettier" },
    typescriptreact = { "prettier" },
    yaml = { "prettier" },
    ["yaml.ghaction"] = { "prettier" },
  },
  default_format_opts = {
    lsp_format = "fallback",
  },
  format_on_save = {
    timeout_ms = 1500,
    lsp_format = "fallback",
  },
})

local lint = require("lint")
lint.linters_by_ft = {
  bash = { "shellcheck" },
  nix = { "deadnix", "statix" },
  sh = { "shellcheck" },
  ["yaml.ghaction"] = { "actionlint" },
}

vim.api.nvim_create_autocmd("BufWritePost", {
  group = vim.api.nvim_create_augroup("lint_on_save", { clear = true }),
  callback = function()
    lint.try_lint()
  end,
})
