-- Clipboard integration -----------------------------------------------------
local opt = vim.opt
local fn = vim.fn
local api = vim.api
local cmd = vim.cmd

opt.clipboard = { "unnamed", "unnamedplus" }

vim.g.clipboard = {
  name = "wl-clipboard",
  copy = {
    ["+"] = "wl-copy",
    ["*"] = "wl-copy",
  },
  paste = {
    ["+"] = "wl-paste --no-newline",
    ["*"] = "wl-paste --no-newline",
  },
  cache_enabled = 1,
}

local function map(mode, lhs, rhs, opts)
  local options = { noremap = true }
  if opts then
    options = vim.tbl_extend("force", options, opts)
  end
  api.nvim_set_keymap(mode, lhs, rhs, options)
end

local keymap = vim.keymap.set

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Appearance -----------------------------------------------------------------
vim.cmd("colorscheme default")
vim.g.edge_style = "default"
vim.g.edge_transparent_background = 2
vim.cmd("colorscheme edge")

require("lualine").setup({
  options = { theme = "edge" },
  sections = {
    lualine_a = { "mode" },
    lualine_b = { "branch", "diff", "diagnostics" },
    lualine_c = { "buffers" },
    lualine_x = { "encoding", "fileformat", "filetype" },
    lualine_y = { "progress" },
    lualine_z = { "location" },
  },
  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = { "filename" },
    lualine_x = { "location" },
    lualine_y = {},
    lualine_z = {},
  },
})

require("fidget").setup({})

require("gitblame").setup({
  enabled = true,
})

require("nvim-tree").setup({
  view = { width = 50 },
  hijack_cursor = true,
  update_focused_file = { enable = true },
})

map("n", "<C-n>", [[<cmd>NvimTreeToggle<CR>]])
map("n", "<leader>r", [[<cmd>NvimTreeRefresh<CR>]])
map("n", "Ń", [[<cmd>NvimTreeFindFile<CR>]])
map("n", "≠", [[<cmd>NvimTreeFindFile<CR>]])
map("n", "<leader>n", [[<cmd>NvimTreeFindFile<CR>]])

map("n", "<leader>ff", [[<cmd>Telescope find_files<CR>]])
map("n", "<leader>fg", ":lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>")
map("n", "<leader>fb", [[<cmd>Telescope buffers<CR>]])
map("n", "<leader>fh", [[<cmd>Telescope help_tags<CR>]])

-- Visual replace without yanking
map("v", "<leader>p", [["_dP]])

if fn.filereadable(fn.expand("~/.config/current-color_scheme")) == 1 then
  local file = assert(io.open(fn.expand("~/.config/current-color_scheme"), "r"))
  local theme = file:read()
  file:close()
  if theme == "prefer-light" then
    vim.g.background = "light"
    vim.o.background = "light"
    cmd("colorscheme edge")
    api.nvim_set_hl(0, "Visual", { bg = "#ffc0cb", fg = "NONE" })
  else
    vim.g.background = "dark"
    vim.o.background = "dark"
    cmd("colorscheme edge")
  end
end

function _G.switch_theme()
  if vim.o.background == "dark" then
    vim.g.background = "light"
    vim.o.background = "light"
    cmd("colorscheme edge")
    api.nvim_set_hl(0, "Visual", { bg = "#ffc0cb", fg = "NONE" })
  else
    vim.g.background = "dark"
    vim.o.background = "dark"
    cmd("colorscheme edge")
  end
end

keymap({ "n", "v", "o" }, "L", "g$", { noremap = true, silent = true })
keymap({ "n", "v", "o" }, "H", "g^", { noremap = true, silent = true })

-- Core options ---------------------------------------------------------------
vim.g.localvimrc_ask = 0

opt.updatetime = 300
opt.timeoutlen = 300
opt.encoding = "utf-8"
opt.scrolloff = 2
opt.showmode = false
opt.hidden = true
opt.wrap = false
opt.joinspaces = false
opt.exrc = true
opt.secure = true
opt.splitright = true
opt.splitbelow = true
opt.formatoptions = "tcrqnb"
opt.incsearch = true
opt.ignorecase = true
opt.smartcase = true
opt.gdefault = true
opt.synmaxcol = 500
opt.laststatus = 2
opt.relativenumber = true
opt.number = true
opt.colorcolumn = "80"
opt.showcmd = true
opt.mouse = "a"
opt.shortmess:append("c")
opt.listchars = { nbsp = "¬", extends = "»", precedes = "«", trail = "•" }
opt.tabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.visualbell = false
opt.foldenable = false
opt.backspace = { "indent", "eol", "start" }
opt.backup = false
opt.writebackup = false

opt.diffopt:append({ "iwhite", "algorithm:patience", "indent-heuristic" })

local undodir = fn.expand("~/.vimdid")
fn.mkdir(undodir, "p")
opt.undodir = undodir
opt.undofile = true

if fn.executable("rg") == 1 then
  vim.o.grepprg = "rg --no-heading --vimgrep"
  vim.o.grepformat = "%f:%l:%c:%m"
elseif fn.executable("ag") == 1 then
  vim.o.grepprg = "ag --nogroup --nocolor"
end

cmd([[filetype plugin indent on]])

-- Search centering
map("n", "n", "nzz")
map("n", "N", "Nzz")
map("n", "*", "*zz")
map("n", "#", "#zz")
map("n", "g*", "g*zz")

map("n", "?", "?\\v")
map("n", "/", "/\\v")
map("c", "%s/", "%sm/")

-- Clipboard helpers ----------------------------------------------------------
local function project_root()
  local bufpath = fn.expand("%:p")
  if bufpath == "" then
    return fn.getcwd()
  end
  local markers = { ".git", ".hg", "package.json", "Cargo.toml", "pyproject.toml", "go.mod" }
  local root_file = vim.fs.find(markers, {
    upward = true,
    stop = vim.loop.os_homedir(),
    path = vim.fs.dirname(bufpath),
  })[1]
  if root_file then
    return vim.fs.dirname(root_file)
  end
  return fn.getcwd()
end

local function relative_file_from_root()
  local abs = fn.expand("%:p")
  if abs == "" then
    return ""
  end
  local root = project_root()
  if abs:sub(1, #root) == root then
    local rel = abs:sub(#root + 2)
    return rel ~= "" and rel or fn.expand("%")
  end
  return fn.expand("%")
end

local function copy_to_clipboard(val)
  fn.setreg("+", val)
end

keymap("n", "<leader>cf", function()
  local rel = relative_file_from_root()
  if rel ~= "" then
    copy_to_clipboard(rel)
    vim.notify("📋 Copied relative path: " .. rel, vim.log.levels.INFO, { title = "Clipboard" })
  else
    vim.notify("⚠️ No file to copy", vim.log.levels.WARN, { title = "Clipboard" })
  end
end, { silent = true, desc = "Copy relative path" })

keymap("n", "<leader>cF", function()
  local abs = fn.expand("%:p")
  if abs ~= "" then
    copy_to_clipboard(abs)
    vim.notify("📋 Copied absolute path: " .. abs, vim.log.levels.INFO, { title = "Clipboard" })
  else
    vim.notify("⚠️ No file to copy", vim.log.levels.WARN, { title = "Clipboard" })
  end
end, { silent = true, desc = "Copy absolute path" })

keymap("n", "<leader>ct", function()
  copy_to_clipboard(fn.expand("%:t"))
end, { silent = true, desc = "Copy filename" })

keymap("n", "<leader>ch", function()
  copy_to_clipboard(fn.expand("%:p:h"))
end, { silent = true, desc = "Copy directory" })

-- Jump CLI integration (github links, markdown references)
keymap("n", "<leader>cg", function()
  local file = fn.expand("%:p")
  local line = fn.line(".")
  local result = fn.system({ "jump", "github-link", "--file", file, "--start-line", tostring(line) })
  if vim.v.shell_error == 0 then
    local ok, parsed = pcall(vim.json.decode, result)
    if ok and parsed.url then
      copy_to_clipboard(parsed.markdown)
      vim.notify("🔗 " .. parsed.markdown, vim.log.levels.INFO)
    else
      vim.notify("❌ Failed to parse result", vim.log.levels.ERROR)
    end
  else
    vim.notify("❌ GitHub link failed", vim.log.levels.ERROR)
  end
end, { silent = true, desc = "Copy GitHub link" })

keymap("v", "<leader>cg", function()
  local start_line = fn.line("v")
  local end_line = fn.line(".")
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  local file = fn.expand("%:p")
  local result = fn.system({
    "jump", "github-link",
    "--file", file,
    "--start-line", tostring(start_line),
    "--end-line", tostring(end_line),
  })
  if vim.v.shell_error == 0 then
    local ok, parsed = pcall(vim.json.decode, result)
    if ok and parsed.url then
      copy_to_clipboard(parsed.markdown)
      vim.notify("🔗 " .. parsed.markdown, vim.log.levels.INFO)
    else
      vim.notify("❌ Failed to parse result", vim.log.levels.ERROR)
    end
  else
    vim.notify("❌ GitHub link failed", vim.log.levels.ERROR)
  end
end, { silent = true, desc = "Copy GitHub link (selection)" })

local function get_lsp_hover_and_definition()
  local bufnr = api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  if #clients == 0 then
    return nil, nil, "No LSP client attached"
  end
  local pos = api.nvim_win_get_cursor(0)
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = { line = pos[1] - 1, character = pos[2] }
  }
  local hover_result = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", params, 5000)
  local def_result = vim.lsp.buf_request_sync(bufnr, "textDocument/definition", params, 5000)
  if not hover_result and not def_result then
    return nil, nil, "LSP timeout or no response"
  end
  return vim.json.encode(hover_result or {}), vim.json.encode(def_result or {}), nil
end

local function copy_markdown_via_lsp(use_github)
  local root = project_root()
  local file = fn.expand("%:p")
  local pos = api.nvim_win_get_cursor(0)
  local line = pos[1]
  local hover_json, def_json, err = get_lsp_hover_and_definition()
  if err then
    vim.notify("❌ LSP error: " .. err, vim.log.levels.ERROR)
    return
  end
  local tmp_hover = os.tmpname()
  local tmp_def = os.tmpname()
  local fh = io.open(tmp_hover, "w")
  if fh then fh:write(hover_json); fh:close() end
  local fd = io.open(tmp_def, "w")
  if fd then fd:write(def_json); fd:close() end
  local cmd_args = {
    "jump", "format-symbol",
    "--root", root,
    "--file", file,
    "--line", tostring(line),
    "--hover-file", tmp_hover,
    "--definition-file", tmp_def,
  }
  if use_github then
    table.insert(cmd_args, "--github")
  end
  local result = vim.trim(fn.system(cmd_args))
  os.remove(tmp_hover)
  os.remove(tmp_def)
  if vim.v.shell_error == 0 and result ~= "" then
    copy_to_clipboard(result)
    local icon = use_github and "🔗" or "📝"
    vim.notify(icon .. " " .. result:sub(1, 60), vim.log.levels.INFO)
  else
    vim.notify("❌ Failed: " .. result, vim.log.levels.ERROR)
  end
end

keymap("n", "<leader>cm", function()
  copy_markdown_via_lsp(false)
end, { silent = true, desc = "Copy markdown reference" })

keymap("n", "<leader>cgl", function()
  copy_markdown_via_lsp(true)
end, { silent = true, desc = "Copy markdown with GitHub link" })

keymap("n", "<leader>cD", function()
  local bufnr = api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  print("LSP clients: " .. #clients)
  for _, client in ipairs(clients) do
    print("  - " .. client.name .. " (id=" .. client.id .. ")")
  end
  local pos = api.nvim_win_get_cursor(0)
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = { line = pos[1] - 1, character = pos[2] }
  }
  local hover = vim.lsp.buf_request_sync(bufnr, "textDocument/hover", params, 5000)
  print("Hover result: " .. vim.inspect(hover))
  local def = vim.lsp.buf_request_sync(bufnr, "textDocument/definition", params, 5000)
  print("Definition result: " .. vim.inspect(def))
  if hover then
    local json = vim.json.encode(hover)
    print("Hover JSON: " .. json:sub(1, 500))
  end
end, { silent = true, desc = "Debug LSP at cursor" })

keymap("n", "<leader>j", function()
  local link = fn.getreg("+")
  if link == "" then
    vim.notify("Clipboard is empty", vim.log.levels.WARN)
    return
  end
  local result = fn.system({ "jump", vim.trim(link) })
  if vim.v.shell_error ~= 0 then
    vim.notify("Jump failed: " .. vim.trim(result), vim.log.levels.ERROR)
  end
end, { silent = true, desc = "Jump to link from clipboard" })

keymap("n", "gj", function()
  local line = api.nvim_get_current_line()
  local col = api.nvim_win_get_cursor(0)[2]
  -- Try to find markdown link [text](url) around cursor
  local link
  for url in line:gmatch("%[.-%]%((.-)%)") do
    local start_pos, end_pos = line:find("%[.-%]%(" .. url:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. "%)")
    if start_pos and col >= start_pos - 1 and col <= end_pos then
      link = url
      break
    end
  end
  -- Fallback: try plain URL under cursor
  if not link then
    link = fn.expand("<cWORD>")
    -- Strip surrounding punctuation
    link = link:match("https?://[^%s%]%)>\"']+") or link
  end
  if link == "" then
    vim.notify("No link under cursor", vim.log.levels.WARN)
    return
  end
  local result = fn.system({ "jump", link })
  if vim.v.shell_error ~= 0 then
    vim.notify("Jump failed: " .. vim.trim(result), vim.log.levels.ERROR)
  end
end, { silent = true, desc = "Jump to link under cursor" })

-- Custom commands ------------------------------------------------------------
local function list_cmd()
  local base = fn.fnamemodify(fn.expand("%"), ":h:.:S")
  if base == "." then
    return "fd --type file --follow"
  end
  return string.format("fd --type file --follow | proximity-sort %s", fn.shellescape(fn.expand("%")))
end

api.nvim_create_user_command("Files", function(opts)
  local source = list_cmd()
  local spec = { source = source, options = "--tiebreak=index" }
  fn["fzf#vim#files"](opts.args, spec, opts.bang and 1 or 0)
end, { bang = true, nargs = "?", complete = "dir" })

api.nvim_create_user_command("Rg", function(opts)
  local pattern = opts.args ~= "" and opts.args or ""
  local search_cmd = string.format(
    "rg --column --line-number --no-heading --color=always %s",
    fn.shellescape(pattern)
  )
  local with_preview = fn["fzf#vim#with_preview"]
  local preview = opts.bang and with_preview("up:60%") or with_preview("right:50%:hidden", "?")
  fn["fzf#vim#grep"](search_cmd, 1, preview, opts.bang and 1 or 0)
end, { bang = true, nargs = "*" })

-- Keymaps --------------------------------------------------------------------
map("n", "<C-p>", "<cmd>Files<CR>")
map("n", "<leader>;", "<cmd>Buffers<CR>")
map("n", "<leader>w", "<cmd>w<CR>")
keymap("n", "<leader>s", ":Rg ", { noremap = true, silent = false, desc = "Ripgrep search" })

keymap("n", "<leader>o", function()
  local dir = fn.expand("%:p:h")
  local path = dir ~= "" and (dir .. "/") or ""
  local escaped = fn.fnameescape(path)
  local keys = api.nvim_replace_termcodes(":edit " .. escaped, true, false, true)
  api.nvim_feedkeys(keys, "n", false)
end, { desc = "Start editing file in current directory" })

map("n", "<leader><leader>", "<C-^>")

keymap("n", "<leader>,", function()
  vim.wo.list = not vim.wo.list
end, { desc = "Toggle listchars" })

map("n", "<leader>q", "g<C-g>")
map("n", "<leader>m", "ct_")

local modes_with_escape = { "n", "i", "v", "s", "x", "o" }
for _, mode in ipairs(modes_with_escape) do
  keymap(mode, "<C-j>", "<Esc>", { noremap = true })
  keymap(mode, "<C-k>", "<Esc>", { noremap = true })
end
keymap("c", "<C-j>", "<C-c>", { noremap = true })
keymap("c", "<C-k>", "<C-c>", { noremap = true })
keymap("l", "<C-j>", "<Esc>", { noremap = true })
keymap("l", "<C-k>", "<Esc>", { noremap = true })
keymap("t", "<C-j>", "<Esc>", { noremap = true })
keymap("t", "<C-k>", "<Esc>", { noremap = true })

keymap({ "n", "v" }, "<C-h>", "<cmd>nohlsearch<CR>", { silent = true })
keymap({ "n", "v" }, "<C-f>", "<cmd>sus<CR>", { silent = true })
keymap("i", "<C-f>", function()
  cmd("sus")
end, { silent = true })

map("n", "<up>", "<nop>")
map("n", "<down>", "<nop>")
map("i", "<up>", "<nop>")
map("i", "<down>", "<nop>")
map("i", "<left>", "<nop>")
map("i", "<right>", "<nop>")

map("n", "<left>", "<cmd>bp<CR>")
map("n", "<right>", "<cmd>bn<CR>")
map("n", "j", "gj")
map("n", "k", "gk")

map("n", "<F1>", "<Esc>")
map("v", "<F1>", "<Esc>")
keymap("i", "<F1>", "<Esc>", { noremap = true })

keymap("n", "<leader>f", "<cmd>Files<CR>", { noremap = true, silent = true })
keymap("n", "<leader>F", "<cmd>FZF ~<CR>", { noremap = true, silent = true })

-- Autocommands ---------------------------------------------------------------
local augroup = api.nvim_create_augroup
local autocmd = api.nvim_create_autocmd

autocmd("BufRead", {
  group = augroup("readonly_buffers", { clear = true }),
  pattern = { "*.orig", "*.pacnew" },
  callback = function(args)
    vim.bo[args.buf].readonly = true
  end,
})

autocmd("InsertLeave", {
  callback = function()
    opt.paste = false
  end,
})

autocmd("BufReadPost", {
  group = augroup("restore_cursor", { clear = true }),
  callback = function(args)
    local file = api.nvim_buf_get_name(args.buf)
    if file:match("/%.git/") then
      return
    end
    local mark = api.nvim_buf_get_mark(args.buf, '"')
    local lcount = api.nvim_buf_line_count(args.buf)
    if mark[1] > 1 and mark[1] <= lcount then
      pcall(api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

autocmd("BufRead", {
  group = augroup("extra_filetypes", { clear = true }),
  pattern = { "*.sbt", "*.sc" },
  callback = function(args)
    vim.bo[args.buf].filetype = "scala"
  end,
})

autocmd("BufRead", {
  group = augroup("custom_filetypes", { clear = true }),
  pattern = "*.plot",
  callback = function(args)
    vim.bo[args.buf].filetype = "gnuplot"
  end,
})

autocmd("BufRead", {
  group = augroup("ld_filetype", { clear = true }),
  pattern = "*.lds",
  callback = function(args)
    vim.bo[args.buf].filetype = "ld"
  end,
})

autocmd("BufRead", {
  group = augroup("tex_filetype", { clear = true }),
  pattern = "*.tex",
  callback = function(args)
    vim.bo[args.buf].filetype = "tex"
  end,
})

autocmd("BufRead", {
  group = augroup("trm_filetype", { clear = true }),
  pattern = "*.trm",
  callback = function(args)
    vim.bo[args.buf].filetype = "c"
  end,
})

autocmd("VimLeave", {
  command = "silent! wshada!",
})

autocmd("FileType", {
  pattern = { "html", "xml", "xsl", "php" },
  callback = function()
    cmd("source ~/.config/nvim/scripts/closetag.vim")
  end,
})

-- Plugins --------------------------------------------------------------------
require("nvim-treesitter.install").compilers = { "gcc" }
require("nvim-treesitter.configs").setup({
  highlight = {
    enable = true,
    disable = {},
    additional_vim_regex_highlighting = false,
  },
})

cmd([[runtime! plugin/python_setup.vim]])

-- Copilot --------------------------------------------------------------------
vim.g.copilot_no_tab_map = true
keymap("i", "<C-S>", 'copilot#Accept("")', { expr = true, silent = true, replace_keycodes = false })
