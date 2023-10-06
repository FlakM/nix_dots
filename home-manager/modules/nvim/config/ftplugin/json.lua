local api = vim.api


local function map(mode, lhs, rhs, opts)
  local options = { noremap = true }
  if opts then
    options = vim.tbl_extend("force", options, opts)
  end
  api.nvim_set_keymap(mode, lhs, rhs, options)
end


-- Format document
map("n", "<leader>JF", [[<cmd>%!jq .<CR>]])
