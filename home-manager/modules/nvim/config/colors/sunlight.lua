-- sunlight.lua — high-contrast warm-white theme optimised for Rust + tree-sitter
-- Designed for outdoor / bright-light conditions (WCAG AAA contrast targets)
-- Test: :colorscheme sunlight   Reload: :colorscheme sunlight

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end
vim.g.colors_name = "sunlight"
vim.o.background = "light"

local hi = function(group, opts)
  vim.api.nvim_set_hl(0, group, opts)
end

-- Palette — hues spread across the full wheel for outdoor legibility
local bg       = "#f5f0e8"  -- warm cream
local bg_dim   = "#ede8e0"  -- cursor line
local bg_menu  = "#f0ebe3"  -- completion popup
local bg_sel   = "#b3d4f0"  -- visual selection
local bg_srch  = "#ffd787"  -- search match
local fg       = "#1c1c1c"  -- near-black
local fg_dim   = "#5a5a5a"  -- punctuation
local fg_muted = "#767676"  -- comments

-- Each role gets a clearly distinct hue — spread across the full wheel
local blue    = "#0060c0"  -- fn, struct, enum, trait, impl   (vivid blue)
local indigo  = "#4400a0"  -- types (user-defined)            (indigo)
local teal    = "#007878"  -- function definitions            (vivid teal)
local teal_m  = "#009090"  -- method calls                    (brighter teal)
local lime    = "#00a020"  -- strings                         (vivid green)
local green   = "#006400"  -- pub, mut, const, static         (forest green)
local orange  = "#c04400"  -- control flow, self, return      (vivid orange)
local amber   = "#c06000"  -- numbers, warnings               (amber)
local red     = "#cc0000"  -- unsafe, panic!, errors          (clear red)
local rose    = "#dd1111"  -- plain variables                 (fresh vivid red)
local violet  = "#7700cc"  -- async                           (vivid violet)
local cyan    = "#007aaa"  -- await                           (vivid cyan — distinct from violet)
local fuchsia = "#bb00bb"  -- macros                          (vivid fuchsia)
local purple  = "#5500aa"  -- constants, Some/None/Ok/Err     (purple)
local gold    = "#9b7800"  -- lifetimes, labels               (golden)
local navy    = "#1a4fa0"  -- modules / path segments         (navy)
local slate   = "#3a5f82"  -- doc comments                    (blue-gray)

-- ── UI ──────────────────────────────────────────────────────────────────────
hi("Normal",       { fg = fg,      bg = bg })
hi("NormalNC",     { fg = fg,      bg = bg })
hi("NormalFloat",  { fg = fg,   bg = "#e4eef8" })   -- cool blue tint, distinct from editor
hi("FloatBorder",  { fg = navy, bg = "#e4eef8" })   -- visible navy border

hi("CursorLine",   { bg = bg_dim })
hi("CursorLineNr", { fg = orange,  bg = bg_dim, bold = true })
hi("LineNr",       { fg = "#aaaaaa" })
hi("ColorColumn",  { bg = "#ece7df" })
hi("SignColumn",   { bg = bg })

hi("Visual",       { bg = bg_sel })
hi("VisualNOS",    { bg = bg_sel })

hi("Search",       { bg = bg_srch, fg = fg })
hi("IncSearch",    { bg = "#ffaf00", fg = "#1c1c1c", bold = true })
hi("CurSearch",    { bg = "#ffaf00", fg = "#1c1c1c", bold = true })
hi("Substitute",   { bg = bg_srch, fg = fg })

hi("StatusLine",   { fg = fg,      bg = "#d4cfc7", bold = true })
hi("StatusLineNC", { fg = fg_dim,  bg = "#ddd8d0" })
hi("TabLine",      { fg = fg_dim,  bg = "#ddd8d0" })
hi("TabLineSel",   { fg = fg,      bg = bg,        bold = true })
hi("TabLineFill",  { bg = "#ddd8d0" })

hi("Pmenu",        { fg = fg,      bg = bg_menu })
hi("PmenuSel",     { fg = fg,      bg = bg_sel,    bold = true })
hi("PmenuSbar",    { bg = "#d4cfc7" })
hi("PmenuThumb",   { bg = "#9a9590" })

hi("WildMenu",     { fg = fg,      bg = bg_sel,    bold = true })
hi("MatchParen",   { bg = bg_srch, bold = true })

hi("Folded",       { fg = fg_dim,  bg = "#e8e3db", italic = true })
hi("FoldColumn",   { fg = "#aaaaaa", bg = bg })

hi("VertSplit",    { fg = "#c0bbb3", bg = bg })
hi("WinSeparator", { fg = "#c0bbb3", bg = bg })

hi("EndOfBuffer",  { fg = "#c8c3bb" })
hi("NonText",      { fg = "#c8c3bb" })
hi("Whitespace",   { fg = "#d4cfc7" })
hi("SpecialKey",   { fg = "#c8c3bb" })

hi("DiffAdd",      { bg = "#d4edda" })
hi("DiffChange",   { bg = "#fff3cd" })
hi("DiffDelete",   { bg = "#f8d7da", fg = "#c0bbb3" })
hi("DiffText",     { bg = "#fce8a0", bold = true })

hi("SpellBad",     { sp = red,     undercurl = true })
hi("SpellCap",     { sp = blue,    undercurl = true })
hi("SpellRare",    { sp = purple,  undercurl = true })
hi("SpellLocal",   { sp = teal,    undercurl = true })

hi("Directory",    { fg = blue,    bold = true })
hi("Title",        { fg = blue,    bold = true })
hi("Question",     { fg = green,   bold = true })
hi("MoreMsg",      { fg = green })
hi("ModeMsg",      { fg = fg,      bold = true })
hi("WarningMsg",   { fg = amber,   bold = true })
hi("ErrorMsg",     { fg = red,     bold = true })

-- ── Syntax (legacy — fallbacks for non-TS) ──────────────────────────────────
hi("Comment",        { fg = fg_muted, italic = true })
hi("Constant",       { fg = purple,   bold = true })
hi("String",         { fg = lime })
hi("Character",      { fg = lime })
hi("Number",         { fg = amber })
hi("Float",          { fg = amber })
hi("Boolean",        { fg = violet,   bold = true })
hi("Identifier",     { fg = rose })
hi("Function",       { fg = teal,     bold = true })
hi("Statement",      { fg = blue,     bold = true })
hi("Conditional",    { fg = orange,   bold = true })
hi("Repeat",         { fg = orange,   bold = true })
hi("Label",          { fg = gold,     italic = true })
hi("Operator",       { fg = "#2d2d2d" })
hi("Keyword",        { fg = blue,     bold = true })
hi("Exception",      { fg = red,      bold = true })
hi("PreProc",        { fg = fuchsia })
hi("Include",        { fg = navy,     bold = true })
hi("Define",         { fg = fuchsia })
hi("Macro",          { fg = fuchsia })
hi("PreCondit",      { fg = fuchsia })
hi("Type",           { fg = indigo,   bold = true })
hi("StorageClass",   { fg = green,    bold = true })
hi("Structure",      { fg = indigo,   bold = true })
hi("Typedef",        { fg = indigo,   bold = true })
hi("Special",        { fg = fuchsia })
hi("SpecialChar",    { fg = fg_dim })
hi("Tag",            { fg = blue })
hi("Delimiter",      { fg = fg_dim })
hi("SpecialComment", { fg = slate,    italic = true })
hi("Debug",          { fg = amber })
hi("Underlined",     { underline = true })
hi("Ignore",         { fg = "#c8c3bb" })
hi("Error",          { fg = red,      bold = true })
hi("Todo",           { fg = orange,   bold = true, bg = "#fff3cd" })

-- ── Tree-sitter ──────────────────────────────────────────────────────────────
hi("@variable",              { fg = rose })
hi("@variable.builtin",      { fg = orange,   bold = true })    -- self
hi("@variable.parameter",    { fg = rose,     italic = true })
hi("@variable.member",       { fg = teal_m })

hi("@constant",              { fg = purple,   bold = true })
hi("@constant.builtin",      { fg = purple,   bold = true })    -- Some None Ok Err
hi("@constant.macro",        { fg = fuchsia,  bold = true })

hi("@module",                { fg = navy })
hi("@module.builtin",        { fg = navy,     bold = true })

hi("@label",                 { fg = gold,     italic = true })

hi("@string",                { fg = lime })
hi("@string.escape",         { fg = orange })
hi("@string.regexp",         { fg = red })
hi("@string.special",        { fg = orange })
hi("@string.special.url",    { fg = blue,     underline = true })

hi("@character",             { fg = lime })
hi("@character.special",     { fg = fg_dim })

hi("@number",                { fg = amber })
hi("@number.float",          { fg = amber })
hi("@boolean",               { fg = violet,   bold = true })

hi("@type",                  { fg = indigo,   bold = true })
hi("@type.builtin",          { fg = blue,     bold = true })    -- u32 str bool etc.
hi("@type.qualifier",        { fg = green,    bold = true })
hi("@type.definition",       { fg = indigo,   bold = true })

hi("@attribute",             { fg = gold,     italic = true })  -- lifetime names
hi("@attribute.builtin",     { fg = gold,     bold = true, italic = true }) -- 'static '_

hi("@function",              { fg = teal,     bold = true })
hi("@function.builtin",      { fg = teal,     bold = true })
hi("@function.call",         { fg = teal })
hi("@function.macro",        { fg = fuchsia })
hi("@function.method",       { fg = teal_m,   bold = true })
hi("@function.method.call",  { fg = teal_m,   bold = true })

hi("@constructor",           { fg = indigo,   bold = true })

hi("@operator",              { fg = "#2d2d2d" })

hi("@keyword",               { fg = blue,     bold = true })
hi("@keyword.function",      { fg = blue,     bold = true })    -- fn
hi("@keyword.type",          { fg = blue,     bold = true })    -- struct enum trait
hi("@keyword.modifier",      { fg = green,    bold = true })    -- pub mut const static
hi("@keyword.coroutine",        { fg = violet,   italic = true })  -- gen fallback
hi("@keyword.coroutine.async",  { fg = violet,   bold = true, italic = true })
hi("@keyword.coroutine.await",  { fg = cyan,     italic = true })
hi("@keyword.exception",     { fg = red,      bold = true })    -- try panic! assert!
hi("@keyword.debug",         { fg = amber,    underline = true }) -- dbg!
hi("@keyword.import",        { fg = navy,     bold = true })    -- use mod
hi("@keyword.conditional",   { fg = orange,   bold = true })    -- if else match
hi("@keyword.repeat",        { fg = orange,   bold = true })    -- loop while for
hi("@keyword.return",        { fg = orange,   bold = true })    -- return yield
hi("@keyword.operator",      { fg = blue,     bold = true })    -- as (cast)

hi("@punctuation.bracket",   { fg = fg_dim })
hi("@punctuation.delimiter", { fg = fg_dim })
hi("@punctuation.special",   { fg = fg_dim })

hi("@comment",               { fg = fg_muted, italic = true })
hi("@comment.documentation", { fg = slate,    italic = true })

-- unsafe — bold + italic + red so it's impossible to miss
hi("@keyword.modifier.unsafe", { fg = red, bold = true, italic = true })

-- ── Diagnostics ─────────────────────────────────────────────────────────────
hi("DiagnosticError",            { fg = red })
hi("DiagnosticWarn",             { fg = amber })
hi("DiagnosticInfo",             { fg = blue })
hi("DiagnosticHint",             { fg = teal })
hi("DiagnosticOk",               { fg = green })
hi("DiagnosticUnderlineError",   { sp = red,    undercurl = true })
hi("DiagnosticUnderlineWarn",    { sp = amber,  undercurl = true })
hi("DiagnosticUnderlineInfo",    { sp = blue,   undercurl = true })
hi("DiagnosticUnderlineHint",    { sp = teal,   undercurl = true })
hi("DiagnosticVirtualTextError", { fg = red,    bg = "#fde8e8", italic = true })
hi("DiagnosticVirtualTextWarn",  { fg = amber,  bg = "#fff8e8", italic = true })
hi("DiagnosticVirtualTextInfo",  { fg = blue,   bg = "#e8f0f8", italic = true })
hi("DiagnosticVirtualTextHint",  { fg = teal,   bg = "#e8f5f5", italic = true })

-- ── LSP ─────────────────────────────────────────────────────────────────────
hi("LspReferenceText",  { bg = bg_dim })
hi("LspReferenceRead",  { bg = "#dceeff" })
hi("LspReferenceWrite", { bg = "#fce8c0" })
hi("LspInlayHint",      { fg = "#888880", bg = "#ece8e0", italic = true })

-- ── GitSigns / Gitgutter ─────────────────────────────────────────────────────
hi("GitSignsAdd",    { fg = green })
hi("GitSignsChange", { fg = amber })
hi("GitSignsDelete", { fg = red })
hi("SignAdd",        { fg = green })
hi("SignChange",     { fg = amber })
hi("SignDelete",     { fg = red })

-- ── Telescope ────────────────────────────────────────────────────────────────
hi("TelescopeNormal",       { fg = fg,     bg = bg_menu })
hi("TelescopeBorder",       { fg = fg_dim, bg = bg_menu })
hi("TelescopePromptNormal", { fg = fg,     bg = "#ece7df" })
hi("TelescopePromptBorder", { fg = fg_dim, bg = "#ece7df" })
hi("TelescopePromptPrefix", { fg = blue,   bg = "#ece7df" })
hi("TelescopeMatching",     { fg = orange, bold = true })
hi("TelescopeSelection",    { bg = bg_sel, bold = true })

-- ── nvim-tree ────────────────────────────────────────────────────────────────
hi("NvimTreeNormal",           { fg = fg,   bg = "#ede8e0" })
hi("NvimTreeFolderName",       { fg = blue })
hi("NvimTreeOpenedFolderName", { fg = blue, bold = true })
hi("NvimTreeRootFolder",       { fg = orange, bold = true })
hi("NvimTreeGitDirty",         { fg = amber })
hi("NvimTreeGitNew",           { fg = green })
hi("NvimTreeGitDeleted",       { fg = red })
hi("NvimTreeExecFile",         { fg = green, bold = true })
hi("NvimTreeSpecialFile",      { fg = purple, bold = true })

-- ── Completion (nvim-cmp) ────────────────────────────────────────────────────
hi("CmpItemAbbrMatch",      { fg = orange,  bold = true })
hi("CmpItemAbbrMatchFuzzy", { fg = orange })
hi("CmpItemKindFunction",   { fg = teal })
hi("CmpItemKindMethod",     { fg = teal })
hi("CmpItemKindField",      { fg = teal })
hi("CmpItemKindVariable",   { fg = fg })
hi("CmpItemKindClass",      { fg = indigo,  bold = true })
hi("CmpItemKindInterface",  { fg = indigo })
hi("CmpItemKindModule",     { fg = navy })
hi("CmpItemKindKeyword",    { fg = blue,    bold = true })
hi("CmpItemKindConstant",   { fg = purple,  bold = true })
hi("CmpItemKindSnippet",    { fg = fuchsia })

-- ── LSP hover border (override handler so K shows a rounded border) ──────────
vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(
  vim.lsp.handlers.hover,
  {
    border     = "rounded",
    max_width  = 80,
    max_height = 40,
    pad_top    = 1,
    pad_bottom = 1,
  }
)
vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(
  vim.lsp.handlers.signature_help,
  {
    border     = "rounded",
    max_width  = 80,
    max_height = 20,
    pad_top    = 1,
    pad_bottom = 1,
  }
)
