-- Git integration for neovim - generates GitHub links for code symbols
-- WARNING: Vibe-coded with Claude, needs testing
-- Main feature: <leader>cl copies LSP symbol as markdown link

-- Helper: Get line range for visual selection or current line
local function get_line_range(use_visual_marks)
  if use_visual_marks then
    local start_line = tonumber(vim.fn.line("'<"))
    local end_line = tonumber(vim.fn.line("'>"))
    return math.min(start_line, end_line), math.max(start_line, end_line)
  end

  local current = tonumber(vim.fn.line("."))
  return current, current
end

-- Format line range as string (e.g., "10" or "10,20")
local function format_range(start_line, end_line)
  if start_line == end_line then
    return tostring(start_line)
  end
  return start_line .. ',' .. end_line
end

-- Get URL from clipboard (tries + register, falls back to ")
local function get_url_from_clipboard()
  local url = vim.fn.getreg('+')
  if url == '' then
    url = vim.fn.getreg('"')
  end
  return url ~= '' and url or nil
end

-- Parse GitHub URL to extract filename and line fragment
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

-- Copy text to system clipboard and default register
local function copy_to_clipboard(text)
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
end

-- Execute GBrowse command (vim-fugitive) for range
local function execute_gbrowse(range_str)
  local ok, err = pcall(vim.cmd, ('silent %sGBrowse!'):format(range_str))
  return ok, err
end

local function copy_github_link_as_markdown(use_visual_marks)
  if vim.fn.exists(':GBrowse') == 0 then
    vim.notify('GBrowse command not found', vim.log.levels.ERROR, { title = 'Git link' })
    return
  end

  local start_line, end_line = get_line_range(use_visual_marks)
  local range_str = format_range(start_line, end_line)

  local ok, err = execute_gbrowse(range_str)
  if not ok then
    vim.notify('GBrowse failed: ' .. err, vim.log.levels.ERROR, { title = 'Git link' })
    return
  end

  vim.defer_fn(function()
    local url = get_url_from_clipboard()
    if not url then
      vim.notify('⚠️ Git link not available', vim.log.levels.WARN, { title = 'Git link' })
      return
    end

    local label, full_url = parse_github_url(url)
    local markdown = string.format('[%s](%s)', label, full_url)

    copy_to_clipboard(markdown)
    vim.notify('🔗 Git ref copied ' .. label, vim.log.levels.INFO, { title = 'Git link' })
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

local function copy_reference_link()
  local params = vim.lsp.util.make_position_params()

  vim.lsp.buf_request(0, 'textDocument/definition', params, function(err, result, ctx, config)
    if err then
      vim.notify('LSP error: ' .. tostring(err), vim.log.levels.ERROR, { title = 'Copy reference' })
      return
    end

    if not result or vim.tbl_isempty(result) then
      vim.notify('No definition found', vim.log.levels.WARN, { title = 'Copy reference' })
      return
    end

    local location = result[1] or result
    local uri = location.uri or location.targetUri
    local range = location.range or location.targetRange

    local filepath = vim.uri_to_fname(uri)
    local line_number = range.start.line + 1

    local cword = vim.fn.expand('<cword>')

    local bufnr = vim.uri_to_bufnr(uri)
    vim.fn.bufload(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, range.start.line, range.start.line + 1, false)
    local line_text = lines[1] or ''

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

    local abs_path_line = filepath .. ':' .. line_number
    vim.fn.setreg('"', abs_path_line)

    vim.notify('📎 Reference copied: ' .. cword .. ' at ' .. relative_path .. ':' .. line_number, vim.log.levels.INFO, { title = 'Copy reference' })
  end)
end

vim.keymap.set('n', '<leader>cr', copy_reference_link, {
  noremap = true,
  silent = true,
  desc = 'Copy reference to identifier under cursor',
})

local function get_symbol_at_cursor()
  local current_line = vim.api.nvim_get_current_line()
  local cursor_col = vim.api.nvim_win_get_cursor(0)[2]

  local identifier_pattern = '[%w_:]+'
  local start_pos = cursor_col + 1

  while start_pos > 1 and current_line:sub(start_pos, start_pos):match('[%w_:]') do
    start_pos = start_pos - 1
  end
  if not current_line:sub(start_pos, start_pos):match('[%w_:]') then
    start_pos = start_pos + 1
  end

  local end_pos = cursor_col + 1
  while end_pos <= #current_line and current_line:sub(end_pos, end_pos):match('[%w_:]') do
    end_pos = end_pos + 1
  end
  end_pos = end_pos - 1

  if start_pos <= end_pos then
    return current_line:sub(start_pos, end_pos)
  end

  return vim.fn.expand('<cword>')
end

local function get_cargo_package_name(filepath)
  local dir = vim.fn.fnamemodify(filepath, ':h')

  for i = 1, 10 do
    local cargo_toml = dir .. '/Cargo.toml'
    if vim.fn.filereadable(cargo_toml) == 1 then
      local lines = vim.fn.readfile(cargo_toml)
      for _, line in ipairs(lines) do
        local name = line:match('^name%s*=%s*"([^"]+)"')
        if name then
          return name:gsub('%-', '_'), dir
        end
      end
    end
    local parent = vim.fn.fnamemodify(dir, ':h')
    if parent == dir then break end
    dir = parent
  end

  return nil, nil
end

local function get_rust_module_path(filepath, cwd)
  local relative = filepath:gsub(cwd .. '/', '')

  local parts = {}
  for part in relative:gmatch('[^/]+') do
    table.insert(parts, part)
  end

  local module_parts = {}
  local in_src = false

  for i, part in ipairs(parts) do
    if part == 'src' then
      in_src = true
    elseif in_src then
      if part:match('%.rs$') then
        local modname = part:gsub('%.rs$', '')
        if modname ~= 'mod' and modname ~= 'lib' and modname ~= 'main' then
          table.insert(module_parts, modname)
        end
      else
        table.insert(module_parts, part)
      end
    end
  end

  return table.concat(module_parts, '::')
end

local function get_treesitter_context(bufnr, line)
  local has_ts, _ = pcall(require, 'nvim-treesitter')
  if not has_ts then
    return nil
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  local root = tree:root()
  local query_string = [[
    (mod_item name: (identifier) @mod.name)
    (impl_item type: (_) @impl.type)
    (struct_item name: (type_identifier) @struct.name)
    (enum_item name: (type_identifier) @enum.name)
    (function_item name: (identifier) @fn.name)
  ]]

  local ok_query, query = pcall(vim.treesitter.query.parse, 'rust', query_string)
  if not ok_query then
    return nil
  end

  local modules = {}
  local current_node = root:descendant_for_range(line - 1, 0, line - 1, 0)

  while current_node do
    local node_type = current_node:type()

    if node_type == 'mod_item' then
      for _, child in ipairs(current_node:field('name')) do
        local mod_name = vim.treesitter.get_node_text(child, bufnr)
        table.insert(modules, 1, mod_name)
      end
    end

    current_node = current_node:parent()
  end

  if #modules > 0 then
    return table.concat(modules, '::')
  end

  return nil
end

local function extract_qualified_name_from_hover(hover_result)
  if not hover_result or not hover_result.contents then
    return nil, nil
  end

  local contents = hover_result.contents
  local text = ''

  if type(contents) == 'string' then
    text = contents
  elseif contents.value then
    text = contents.value
  elseif contents.kind == 'markdown' then
    text = contents.value
  elseif type(contents) == 'table' and contents[1] then
    if type(contents[1]) == 'string' then
      text = contents[1]
    elseif contents[1].value then
      text = contents[1].value
    end
  end

  if text == '' then
    return nil, nil
  end

  local type_kind = nil
  local qualified_name = nil

  local rust_patterns = {
    { pattern = '```rust\n(pub%s+)?(struct)%s+([%w_:]+)', type_idx = 2, name_idx = 3 },
    { pattern = '```rust\n(pub%s+)?(enum)%s+([%w_:]+)', type_idx = 2, name_idx = 3 },
    { pattern = '```rust\n(pub%s+)?(trait)%s+([%w_:]+)', type_idx = 2, name_idx = 3 },
    { pattern = '```rust\n(pub%s+)?(type)%s+([%w_:]+)', type_idx = 2, name_idx = 3 },
    { pattern = '```rust\n(pub%s+)?(const)%s+([%w_:]+)', type_idx = 2, name_idx = 3 },
    { pattern = '```rust\n(pub%s+)?(static)%s+([%w_:]+)', type_idx = 2, name_idx = 3 },
    { pattern = '```rust\n(pub%s+)?(async%s+)?(fn)%s+([%w_:]+)', type_idx = 3, name_idx = 4 },
  }

  for _, entry in ipairs(rust_patterns) do
    local matches = {text:match(entry.pattern)}
    if #matches >= entry.name_idx then
      type_kind = matches[entry.type_idx]
      local raw_name = matches[entry.name_idx]
      qualified_name = raw_name:match('^([%w_:]+)')
      if qualified_name and qualified_name:find('::') then
        return qualified_name, type_kind
      end
    end
  end

  local generic_patterns = {
    { pattern = '(fn)%s+([%w_:]+)', type_idx = 1, name_idx = 2 },
    { pattern = '(struct)%s+([%w_:]+)', type_idx = 1, name_idx = 2 },
    { pattern = '(enum)%s+([%w_:]+)', type_idx = 1, name_idx = 2 },
    { pattern = '(trait)%s+([%w_:]+)', type_idx = 1, name_idx = 2 },
    { pattern = '(class)%s+([%w_.]+)', type_idx = 1, name_idx = 2 },
    { pattern = '(interface)%s+([%w_.]+)', type_idx = 1, name_idx = 2 },
    { pattern = '(function)%s+([%w_.]+)', type_idx = 1, name_idx = 2 },
    { pattern = '(def)%s+([%w_.]+)', type_idx = 1, name_idx = 2 },
  }

  for _, entry in ipairs(generic_patterns) do
    local matches = {text:match(entry.pattern)}
    if #matches >= 2 then
      type_kind = matches[entry.type_idx]
      qualified_name = matches[entry.name_idx]:match('^([%w_:%.]+)')
      if qualified_name and (qualified_name:find('::') or qualified_name:find('%.')) then
        return qualified_name, type_kind
      end
    end
  end

  return nil, nil
end

-- Map LSP SymbolKind enum to readable type names
-- See: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#symbolKind
local function symbol_kind_to_type(kind)
  local kinds = {
    [2] = "module",
    [5] = "class",
    [6] = "fn",
    [8] = "field",
    [10] = "enum",
    [11] = "trait",
    [12] = "fn",
    [13] = "static",
    [14] = "const",
    [22] = "enum variant",
    [23] = "struct",
  }
  return kinds[kind]
end

local function get_rust_analyzer_symbol_info(params, callback)
  local clients = vim.lsp.get_active_clients({ name = "rust-analyzer" })
  if #clients == 0 then
    callback(nil)
    return
  end

  local client = clients[1]

  client.request('textDocument/documentSymbol', {
    textDocument = params.textDocument
  }, function(err, result)
    if err or not result then
      callback(nil)
      return
    end

    local function find_symbol_at_position(symbols, line, col)
      for _, sym in ipairs(symbols) do
        local range = sym.range or sym.location and sym.location.range
        if range then
          local start_line = range.start.line
          local end_line = range['end'].line
          local start_char = range.start.character
          local end_char = range['end'].character

          if line >= start_line and line <= end_line then
            if line == start_line and col < start_char then
              goto continue
            end
            if line == end_line and col > end_char then
              goto continue
            end

            if sym.children then
              local child_result = find_symbol_at_position(sym.children, line, col)
              if child_result then
                return child_result
              end
            end

            local type_from_kind = symbol_kind_to_type(sym.kind)
            return {
              name = sym.name,
              kind = sym.kind,
              detail = sym.detail,
              type_kind = type_from_kind
            }
          end
        end
        ::continue::
      end
      return nil
    end

    local line = params.position.line
    local col = params.position.character
    local symbol_info = find_symbol_at_position(result, line, col)
    callback(symbol_info)
  end, 0)
end

-- Debug logging to /tmp/nvim_lsp_ref.log
local function log_debug(msg)
  local log_file = '/tmp/nvim_lsp_ref.log'
  local f = io.open(log_file, 'a')
  if f then
    f:write(os.date('%Y-%m-%d %H:%M:%S') .. ' ' .. msg .. '\n')
    f:close()
  end
end

-- Copy LSP reference as markdown link
--
-- Generates markdown links in the format: [type qualified::name](url)
-- Examples:
--   [struct my_crate::module::MyStruct](https://github.com/...)
--   [fn my_crate::my_function](https://github.com/...)
--   [macro std::println](https://github.com/...)
--
-- Strategy:
-- 1. Use rust-analyzer's documentSymbol to find the symbol at cursor
--    - This works for: structs, enums, traits, functions, fields, modules, consts, statics
--    - Macros are NOT in documentSymbol tree, so we fall back to hover
-- 2. Build qualified name by traversing parent symbols (modules, traits, structs)
-- 3. Prepend crate name from Cargo.toml
-- 4. Use textDocument/definition to get file location
-- 5. Use GBrowse (vim-fugitive) to generate GitHub URL
-- 6. Fall back to local file path if not in git repo
--
-- Special cases:
-- - Trait methods: Detected by function inside trait, labeled as "trait method"
-- - Macros: Not in symbol tree, so we use hover text to extract macro name
-- - Fields: Include parent struct/enum in path
local function copy_lsp_reference_as_markdown()
  log_debug('=== copy_lsp_reference_as_markdown called ===')

  local clients = vim.lsp.get_active_clients({ name = "rust-analyzer" })
  log_debug('Found ' .. #clients .. ' rust-analyzer clients')

  if #clients == 0 then
    vim.notify('rust-analyzer not active', vim.log.levels.WARN)
    return
  end

  local params = vim.lsp.util.make_position_params()
  log_debug('Position: line=' .. params.position.line .. ' char=' .. params.position.character)

  -- Step 1: Try to get symbol from documentSymbol (works for most symbols except macros)
  clients[1].request('textDocument/documentSymbol', { textDocument = params.textDocument }, function(err, symbols)
    log_debug('documentSymbol callback: err=' .. tostring(err) .. ' symbols=' .. tostring(symbols ~= nil))

    if err then
      vim.notify('documentSymbol error: ' .. tostring(err), vim.log.levels.ERROR)
      return
    end
    if not symbols then
      vim.notify('No symbols found', vim.log.levels.WARN)
      return
    end

    local pos = params.position
    -- Find the deepest symbol containing the cursor position
    local function find_symbol(syms, line, col)
      for _, s in ipairs(syms) do
        local r = s.range
        if r and line >= r.start.line and line <= r['end'].line then
          if s.children then
            local child = find_symbol(s.children, line, col)
            if child then return child end
          end
          return s
        end
      end
    end

    local sym = find_symbol(symbols, pos.line, pos.character)
    log_debug('Found symbol: ' .. tostring(sym and sym.name or 'nil') .. ' kind: ' .. tostring(sym and sym.kind or 'nil'))

    local type_kind = symbol_kind_to_type(sym and sym.kind)
    log_debug('Type kind: ' .. tostring(type_kind))

    -- Check if cursor is on a word that ends with '!' (likely a macro)
    -- Macros don't appear in documentSymbol, so we need hover to identify them
    local cursor_word = vim.fn.expand('<cWORD>')
    local is_likely_macro = cursor_word:match('!') ~= nil
    log_debug('Cursor word: ' .. cursor_word .. ' is_likely_macro: ' .. tostring(is_likely_macro))

    -- Helper: Build qualified name from symbol path
    -- Traverses parent symbols (modules, traits, structs, enums, enum variants) to build full path
    -- Avoids duplicating the target symbol name if it's already in the tree
    local function build_qualified_name(sym_name, symbols_list, target_line, target_kind)
      local path_parts = {}
      local parent_kind = nil
      local found_self = false
      local function traverse(syms)
        for _, s in ipairs(syms) do
          local r = s.range
          if r and target_line >= r.start.line and target_line <= r['end'].line then
            -- Include: modules(2), classes(5), enums(10), traits(11), enum variants(22), structs(23)
            if s.kind == 2 or s.kind == 5 or s.kind == 10 or s.kind == 11 or s.kind == 22 or s.kind == 23 then
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
      traverse(symbols_list)
      if not found_self then
        table.insert(path_parts, sym_name)
      end
      local qualified = table.concat(path_parts, '::')

      if target_kind == 6 and parent_kind == 11 then
        return qualified, "trait method"
      end
      return qualified, nil
    end

    -- Step 3: Get definition location and build final markdown
    -- This function is called either directly (for regular symbols) or after hover (for macros)
    local function proceed_with_definition()
    vim.lsp.buf_request(0, 'textDocument/definition', params, function(def_err, result)
      log_debug('definition callback: err=' .. tostring(def_err) .. ' result=' .. tostring(result ~= nil))

      if def_err then
        vim.notify('definition error: ' .. tostring(def_err), vim.log.levels.ERROR)
        return
      end
      if not result or vim.tbl_isempty(result) then
        vim.notify('No definition found', vim.log.levels.WARN)
        return
      end

      local loc = result[1] or result
      local filepath = vim.uri_to_fname(loc.uri or loc.targetUri)
      local line_num = (loc.range or loc.targetRange).start.line + 1
      log_debug('Definition at: ' .. filepath .. ':' .. line_num)

      local temp_buf = vim.fn.bufadd(filepath)
      vim.fn.bufload(temp_buf)
      vim.cmd('split')
      local temp_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(temp_win, temp_buf)
      vim.api.nvim_win_set_cursor(temp_win, {line_num, 0})

      local orig_clip = vim.fn.getreg('+')
      vim.fn.setreg('+', '')

      local ok, err_msg = pcall(function() vim.cmd(line_num .. 'GBrowse!') end)
      log_debug('GBrowse ok=' .. tostring(ok) .. ' err=' .. tostring(err_msg))

      vim.cmd('close')

      local function get_crate_name(fp)
        local dir = vim.fn.fnamemodify(fp, ':p:h')
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

      local name = sym and sym.name or vim.fn.expand('<cword>')
      local qualified, override_kind

      -- For macros, use the full qualified name from hover (already includes crate)
      if sym and sym.is_macro then
        qualified = name
        override_kind = type_kind
      else
        -- For regular symbols, build qualified name from symbol tree
        qualified, override_kind = build_qualified_name(name, symbols, pos.line, sym and sym.kind)
        local crate_name = get_crate_name(filepath)
        if crate_name and not qualified:find(crate_name) then
          qualified = crate_name .. '::' .. qualified
        end
      end

      local final_kind = override_kind or type_kind
      local display = final_kind and (final_kind .. ' ' .. qualified) or qualified

      if not ok then
        log_debug('GBrowse failed, using local path')
        local fallback = string.format('[%s](%s:%d)', display, filepath, line_num)
        copy_to_clipboard(fallback)
        vim.notify('📎 Local: ' .. display, vim.log.levels.INFO)
        return
      end

      vim.defer_fn(function()
        local url = vim.fn.getreg('+')
        log_debug('URL from clipboard: ' .. tostring(url))

        if not url or url == '' or url:match('^%[') then
          vim.notify('No URL in clipboard', vim.log.levels.WARN)
          vim.fn.setreg('+', orig_clip)
          return
        end

        local markdown = string.format('[%s](%s)', display, url)
        log_debug('Final markdown: ' .. markdown)

        copy_to_clipboard(markdown)
        vim.notify('🔗 ' .. display, vim.log.levels.INFO)
      end, 100)
    end)
    end

    -- Step 2: For macros, use hover to get the macro name since they're not in documentSymbol
    -- This fallback handles cases like println!, vec!, etc.
    if is_likely_macro then
      vim.lsp.buf_request(0, 'textDocument/hover', params, function(hover_err, hover_result)
        log_debug('Macro hover callback: err=' .. tostring(hover_err))

        if not hover_err and hover_result and hover_result.contents then
          local contents = hover_result.contents
          local text = type(contents) == 'string' and contents
                    or contents.value
                    or (type(contents) == 'table' and contents[1] and
                        (type(contents[1]) == 'string' and contents[1] or contents[1].value))

          if text then
            log_debug('Hover text: ' .. text:sub(1, 200))
            -- Extract macro name from hover text
            -- Format is typically:
            --   ```rust
            --   std::macros
            --   ```
            --   ```rust
            --   macro_rules! println
            --   ```
            local module_path = text:match('```rust\n([%w_:]+)\n```')
            local macro_simple_name = text:match('macro_rules!%s+([%w_]+)')

            local macro_name
            if module_path and macro_simple_name then
              macro_name = module_path .. '::' .. macro_simple_name
              log_debug('Extracted macro: module=' .. module_path .. ' name=' .. macro_simple_name)
            elseif macro_simple_name then
              macro_name = macro_simple_name
              log_debug('Extracted macro name only: ' .. macro_simple_name)
            end

            if macro_name then
              log_debug('Final macro name: ' .. macro_name)
              -- For macros, store the full qualified name and override the type
              sym = { name = macro_name, kind = nil, is_macro = true }
              type_kind = 'macro'
            else
              log_debug('Failed to extract macro name from hover')
            end
          end
        end

        -- Continue with definition lookup
        proceed_with_definition()
      end)
    else
      -- If not a macro, proceed directly with definition
      proceed_with_definition()
    end
  end, 0)
end

vim.keymap.set('n', '<leader>cl', copy_lsp_reference_as_markdown, {
  noremap = true,
  silent = true,
  desc = 'Copy LSP reference as markdown [symbol](link)',
})
