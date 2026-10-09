local gitsigns = require("gitsigns")

gitsigns.setup({
  current_line_blame = false,
  signs_staged_enable = true,
  word_diff = false,
  on_attach = function(bufnr)
    local function map(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
    end

    map("n", "]c", function()
      if vim.wo.diff then
        vim.cmd.normal({ "]c", bang = true })
      else
        gitsigns.nav_hunk("next")
      end
    end, "Next git hunk")
    map("n", "[c", function()
      if vim.wo.diff then
        vim.cmd.normal({ "[c", bang = true })
      else
        gitsigns.nav_hunk("prev")
      end
    end, "Previous git hunk")
    map("n", "<leader>hs", gitsigns.stage_hunk, "Stage git hunk")
    map("x", "<leader>hs", function()
      gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
    end, "Stage git hunk")
    map("n", "<leader>hr", gitsigns.reset_hunk, "Reset git hunk")
    map("x", "<leader>hr", function()
      gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
    end, "Reset git hunk")
    map("n", "<leader>hp", gitsigns.preview_hunk_inline, "Preview git hunk")
    map("n", "<leader>hb", function()
      gitsigns.blame_line({ full = true })
    end, "Blame line")
    map("n", "<leader>hd", gitsigns.diffthis, "Diff current file")
    map({ "o", "x" }, "ih", gitsigns.select_hunk, "Git hunk")
  end,
})
