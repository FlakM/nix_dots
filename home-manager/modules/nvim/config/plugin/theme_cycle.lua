-- Cycle through 3 themes with Ctrl+Alt+N
-- 1. dark      — edge dark
-- 2. white     — edge light (clean white)
-- 3. sunlight  — warm-cream high-contrast outdoor theme
-- Also syncs kitty terminal via ~/.config/kitty/switch.sh

local themes = {
  {
    name  = "dark",
    apply = function()
      vim.o.background = "dark"
      vim.cmd("colorscheme edge")
    end,
  },
  {
    name  = "white",
    apply = function()
      vim.o.background = "light"
      vim.cmd("colorscheme edge")
      vim.api.nvim_set_hl(0, "Visual", { bg = "#ffc0cb", fg = "NONE" })
    end,
  },
  {
    name  = "sunlight",
    apply = function()
      vim.o.background = "light"
      vim.cmd("colorscheme sunlight")
    end,
  },
}

local current = 1

-- Sync index with whatever theme init.lua applied at startup
vim.schedule(function()
  local cs = vim.g.colors_name or ""
  if cs == "sunlight" then
    current = 3
  elseif vim.o.background == "light" then
    current = 2
  else
    current = 1
  end
end)

local function sync_kitty(mode)
  local switch_sh = vim.fn.expand("~/.config/kitty/switch.sh")
  if vim.fn.filereadable(switch_sh) == 1 then
    vim.fn.jobstart({ switch_sh, mode }, { detach = true })
  end
end

local function cycle()
  current = (current % #themes) + 1
  themes[current].apply()
  sync_kitty(themes[current].name)
  vim.notify("Theme: " .. themes[current].name, vim.log.levels.INFO)
end

vim.keymap.set("n", "<C-M-n>", cycle, { silent = true, desc = "Cycle theme (dark / white / sunlight)" })
