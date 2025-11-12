
local function find_buf_yaml(path)
    local current = path
    while current ~= "/" do
        local buf_yaml = current .. "/buf.yaml"
        if vim.fn.filereadable(buf_yaml) == 1 then
            return buf_yaml
        end
        current = vim.fn.fnamemodify(current, ":h")
    end
    return nil
end

local function format_proto()
    local bufnr = vim.api.nvim_get_current_buf()
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    local dirpath = vim.fn.fnamemodify(filepath, ":h")

    if find_buf_yaml(dirpath) then
        vim.cmd("write")
        vim.fn.system(string.format("buf format -w %s", vim.fn.shellescape(filepath)))
        vim.cmd("edit!")
    else
        vim.lsp.buf.format({ async = false })
    end
end

require'lspconfig'.protols.setup{
    on_attach = function(client, bufnr)
        local buf_yaml_found = find_buf_yaml(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":h"))
        if buf_yaml_found then
            client.server_capabilities.documentFormattingProvider = false
            vim.keymap.set('n', '<leader>f', format_proto, { buffer = bufnr, desc = 'Format proto with buf' })
        end
    end,
}

vim.api.nvim_create_autocmd("FileType", {
    pattern = "proto",
    callback = function()
        vim.api.nvim_buf_create_user_command(0, 'Format', format_proto, { desc = 'Format proto file' })
    end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = "*.proto",
    callback = format_proto,
})
