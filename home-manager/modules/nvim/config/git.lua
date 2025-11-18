-- ============================================================================
-- Git integration: Generate GitHub/GitLab markdown links for code symbols
-- ============================================================================
--
-- Features:
--   <leader>cg - Copy GitHub link as markdown (normal/visual mode)
--   <leader>cr - Copy file:line reference to LSP symbol definition
--   <leader>cl - Copy LSP symbol as markdown link [type crate::path](url)
--
-- Requirements: vim-fugitive (for GBrowse), LSP (for symbol navigation)
--
-- ============================================================================
-- Utilities
-- ============================================================================

local function copy_to_clipboard(text)
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
end

local function get_clipboard_text()
  local text = vim.fn.getreg('+')
  if text == '' then
    text = vim.fn.getreg('"')
  end
  return text ~= '' and text or nil
end

-- ============================================================================
-- GitHub Link Generation (vim-fugitive integration)
-- ============================================================================

local function get_line_range(use_visual_marks)
  if use_visual_marks then
    local start_line = tonumber(vim.fn.line("'<"))
    local end_line = tonumber(vim.fn.line("'>"))
    return math.min(start_line, end_line), math.max(start_line, end_line)
  end
  local current = tonumber(vim.fn.line("."))
  return current, current
end

local function format_range(start_line, end_line)
  if start_line == end_line then
    return tostring(start_line)
  end
  return start_line .. ',' .. end_line
end

local function parse_github_url(url)
  local base, fragment = url:match('([^#]+)(#.*)?$')
  base = base or url

  local path_without_query = base:match('([^?]+)') or base
  local filename = path_without_query:match('([^/]+)$') or path_without_query

  local label
  if fragment and fragment:match('#L') then
    label = filename .. ':' .. fragment:sub(2)
  else
    label = filename .. (fragment or '')
  end

  return label, url
end

local function copy_github_link_as_markdown(use_visual_marks)
  if vim.fn.exists(':GBrowse') == 0 then
    vim.notify('GBrowse command not found', vim.log.levels.ERROR)
    return
  end

  local start_line, end_line = get_line_range(use_visual_marks)
  local range_str = format_range(start_line, end_line)

  local ok, err = pcall(vim.cmd, ('silent %sGBrowse!'):format(range_str))
  if not ok then
    vim.notify('GBrowse failed: ' .. err, vim.log.levels.ERROR)
    return
  end

  vim.defer_fn(function()
    local url = get_clipboard_text()
    if not url then
      vim.notify('Git link not available', vim.log.levels.WARN)
      return
    end

    local label, full_url = parse_github_url(url)
    local markdown = string.format('[%s](%s)', label, full_url)
    copy_to_clipboard(markdown)
    vim.notify('Copied: ' .. label, vim.log.levels.INFO)
  end, 50)
end

local function handle_visual_mode()
  local start_line = vim.fn.line('v')
  local end_line = vim.fn.line('.')
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
  vim.fn.setpos("'<", {0, math.min(start_line, end_line), 1, 0})
  vim.fn.setpos("'>", {0, math.max(start_line, end_line), 999, 0})
  vim.schedule(function()
    copy_github_link_as_markdown(true)
  end)
end

-- ============================================================================
-- LSP Reference: File:Line
-- ============================================================================

local function copy_reference_link()
  local params = vim.lsp.util.make_position_params()

  vim.lsp.buf_request(0, 'textDocument/definition', params, function(err, result)
    if err or not result or vim.tbl_isempty(result) then
      vim.notify(err and ('LSP error: ' .. tostring(err)) or 'No definition found', vim.log.levels.ERROR)
      return
    end

    local location = result[1] or result
    local uri = location.uri or location.targetUri
    local range = location.range or location.targetRange
    local filepath = vim.uri_to_fname(uri)
    local line_number = range.start.line + 1

    local bufnr = vim.uri_to_bufnr(uri)
    vim.fn.bufload(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, range.start.line, range.start.line + 1, false)
    local line_text = lines[1] or ''

    local cword = vim.fn.expand('<cword>')
    local col = range.start.character
    local end_col = range['end'].character
    if col and end_col and line_text then
      local symbol = line_text:sub(col + 1, end_col)
      if symbol ~= '' then
        cword = symbol
      end
    end

    local relative_path = filepath:gsub(vim.fn.getcwd() .. '/', '')
    vim.fn.setreg('+', relative_path .. ':' .. line_number)
    vim.fn.setreg('"', filepath .. ':' .. line_number)
    vim.notify('Copied: ' .. cword .. ' at ' .. relative_path .. ':' .. line_number, vim.log.levels.INFO)
  end)
end

-- ============================================================================
-- Rust-specific helpers
-- ============================================================================

local function get_crate_name(filepath)
  local dir = vim.fn.fnamemodify(filepath, ':p:h')
  while dir ~= '/' do
    local cargo = dir .. '/Cargo.toml'
    if vim.fn.filereadable(cargo) == 1 then
      for _, line in ipairs(vim.fn.readfile(cargo)) do
        local name = line:match('^name%s*=%s*"([^"]+)"')
        if name then return name:gsub('%-', '_') end
      end
    end
    dir = vim.fn.fnamemodify(dir, ':h')
  end
  return nil
end

local SYMBOL_KIND = {
  MODULE = 2,
  CLASS = 5,
  FUNCTION = 6,
  FIELD = 8,
  ENUM = 10,
  TRAIT = 11,
  METHOD = 12,
  STATIC = 13,
  CONST = 14,
  ENUM_VARIANT = 22,
  STRUCT = 23,
}

local SYMBOL_KIND_NAMES = {
  [SYMBOL_KIND.MODULE] = "module",
  [SYMBOL_KIND.CLASS] = "class",
  [SYMBOL_KIND.FUNCTION] = "fn",
  [SYMBOL_KIND.FIELD] = "field",
  [SYMBOL_KIND.ENUM] = "enum",
  [SYMBOL_KIND.TRAIT] = "trait",
  [SYMBOL_KIND.METHOD] = "fn",
  [SYMBOL_KIND.STATIC] = "static",
  [SYMBOL_KIND.CONST] = "const",
  [SYMBOL_KIND.ENUM_VARIANT] = "enum variant",
  [SYMBOL_KIND.STRUCT] = "struct",
}

local function symbol_kind_to_type(kind)
  return SYMBOL_KIND_NAMES[kind]
end

-- ============================================================================
-- LSP Reference: Rust-analyzer markdown link generation
-- ============================================================================
--
-- Generates markdown links: [type qualified::name](url)
-- Examples: [struct my_crate::module::MyStruct](https://github.com/...)
--           [fn my_crate::my_function](https://github.com/...)
--           [macro std::println](https://github.com/...)

local function find_symbol_at_position(symbols, line, col)
  for _, s in ipairs(symbols) do
    local r = s.range
    if r and line >= r.start.line and line <= r['end'].line then
      if s.children then
        local child = find_symbol_at_position(s.children, line, col)
        if child then return child end
      end
      return s
    end
  end
end

local INCLUDED_SYMBOL_KINDS = {
  [SYMBOL_KIND.MODULE] = true,
  [SYMBOL_KIND.CLASS] = true,
  [SYMBOL_KIND.ENUM] = true,
  [SYMBOL_KIND.TRAIT] = true,
  [SYMBOL_KIND.ENUM_VARIANT] = true,
  [SYMBOL_KIND.STRUCT] = true,
}

local function build_qualified_name(sym_name, symbols, target_line, target_kind)
  local path_parts = {}
  local parent_kind = nil
  local found_self = false

  local function traverse(syms)
    for _, s in ipairs(syms) do
      local r = s.range
      if r and target_line >= r.start.line and target_line <= r['end'].line then
        if INCLUDED_SYMBOL_KINDS[s.kind] then
          if s.name == sym_name and s.kind == target_kind then
            found_self = true
          end
          table.insert(path_parts, s.name)
          parent_kind = s.kind
        end
        if s.children then
          traverse(s.children)
        end
      end
    end
  end

  traverse(symbols)
  if not found_self then
    table.insert(path_parts, sym_name)
  end

  local qualified = table.concat(path_parts, '::')
  if target_kind == SYMBOL_KIND.FUNCTION and parent_kind == SYMBOL_KIND.TRAIT then
    return qualified, "trait method"
  end
  return qualified, nil
end

local function extract_macro_from_hover(hover_result)
  if not hover_result or not hover_result.contents then
    return nil
  end

  local contents = hover_result.contents
  local text = type(contents) == 'string' and contents
            or contents.value
            or (type(contents) == 'table' and contents[1] and
                (type(contents[1]) == 'string' and contents[1] or contents[1].value))

  if not text then return nil end

  local module_path = text:match('```rust\n([%w_:]+)\n```')
  local macro_name = text:match('macro_rules!%s+([%w_]+)')

  if module_path and macro_name then
    return module_path .. '::' .. macro_name
  elseif macro_name then
    return macro_name
  end
  return nil
end

local function generate_github_url_for_file(filepath, line_num)
  local temp_buf = vim.fn.bufadd(filepath)
  vim.fn.bufload(temp_buf)
  vim.cmd('split')
  local temp_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(temp_win, temp_buf)
  vim.api.nvim_win_set_cursor(temp_win, {line_num, 0})

  local orig_clip = vim.fn.getreg('+')
  vim.fn.setreg('+', '')

  local ok, err_msg = pcall(function() vim.cmd(line_num .. 'GBrowse!') end)
  vim.cmd('close')

  if not ok then
    return nil, orig_clip
  end

  return vim.fn.getreg('+'), orig_clip
end

local function copy_lsp_reference_as_markdown()
  local clients = vim.lsp.get_active_clients({ name = "rust-analyzer" })
  if #clients == 0 then
    vim.notify('rust-analyzer not active', vim.log.levels.WARN)
    return
  end

  local params = vim.lsp.util.make_position_params()

  clients[1].request('textDocument/documentSymbol', { textDocument = params.textDocument }, function(err, symbols)
    if err or not symbols then
      vim.notify(err and ('documentSymbol error: ' .. tostring(err)) or 'No symbols found', vim.log.levels.ERROR)
      return
    end

    local pos = params.position
    local sym = find_symbol_at_position(symbols, pos.line, pos.character)
    local type_kind = symbol_kind_to_type(sym and sym.kind)

    local cursor_word = vim.fn.expand('<cWORD>')
    local is_likely_macro = cursor_word:match('!') ~= nil

    local function proceed_with_definition()
      vim.lsp.buf_request(0, 'textDocument/definition', params, function(def_err, result)
        if def_err or not result or vim.tbl_isempty(result) then
          vim.notify(def_err and ('definition error: ' .. tostring(def_err)) or 'No definition found', vim.log.levels.ERROR)
          return
        end

        local loc = result[1] or result
        local filepath = vim.uri_to_fname(loc.uri or loc.targetUri)
        local line_num = (loc.range or loc.targetRange).start.line + 1

        local name = sym and sym.name or vim.fn.expand('<cword>')
        local qualified, override_kind

        if sym and sym.is_macro then
          qualified = name
          override_kind = type_kind
        else
          qualified, override_kind = build_qualified_name(name, symbols, pos.line, sym and sym.kind)
          local crate_name = get_crate_name(filepath)
          if crate_name and not qualified:find(crate_name) then
            qualified = crate_name .. '::' .. qualified
          end
        end

        local final_kind = override_kind or type_kind
        local display = final_kind and (final_kind .. ' ' .. qualified) or qualified

        local url, orig_clip = generate_github_url_for_file(filepath, line_num)
        if not url then
          local fallback = string.format('[%s](%s:%d)', display, filepath, line_num)
          copy_to_clipboard(fallback)
          vim.notify('Local: ' .. display, vim.log.levels.INFO)
          return
        end

        vim.defer_fn(function()
          if not url or url == '' or url:match('^%[') then
            vim.notify('No URL in clipboard', vim.log.levels.WARN)
            vim.fn.setreg('+', orig_clip)
            return
          end

          local markdown = string.format('[%s](%s)', display, url)
          copy_to_clipboard(markdown)
          vim.notify('Copied: ' .. display, vim.log.levels.INFO)
        end, 100)
      end)
    end

    if is_likely_macro then
      vim.lsp.buf_request(0, 'textDocument/hover', params, function(hover_err, hover_result)
        if not hover_err and hover_result then
          local macro_name = extract_macro_from_hover(hover_result)
          if macro_name then
            sym = { name = macro_name, kind = nil, is_macro = true }
            type_kind = 'macro'
          end
        end
        proceed_with_definition()
      end)
    else
      proceed_with_definition()
    end
  end, 0)
end

-- ============================================================================
-- Keymaps
-- ============================================================================

vim.keymap.set('n', '<leader>cg', copy_github_link_as_markdown, {
  noremap = true,
  silent = true,
  desc = 'Copy GitHub link as Markdown',
})

vim.keymap.set('v', '<leader>cg', handle_visual_mode, {
  noremap = true,
  silent = true,
  desc = 'Copy GitHub link as Markdown (range)',
})

vim.keymap.set('n', '<leader>cr', copy_reference_link, {
  noremap = true,
  silent = true,
  desc = 'Copy reference to identifier under cursor',
})

vim.keymap.set('n', '<leader>cl', copy_lsp_reference_as_markdown, {
  noremap = true,
  silent = true,
  desc = 'Copy LSP reference as markdown [symbol](link)',
})
