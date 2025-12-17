local map = vim.keymap.set
local dap = require('dap')

local rust_analyzer_path = vim.fn.exepath("rust-analyzer")
if rust_analyzer_path == "" then
    rust_analyzer_path = "rust-analyzer"
end

-- Toggle runnables
map("n", "<leader>dr", function()
    vim.cmd.RustLsp('debug')
end)


-- Run check
map("n", "<leader>cc", function()
    vim.cmd.RustLsp('flyCheck')
end)

-- Toggle debuggables
map("n", "<leader>dd", function()
    vim.cmd.RustLsp('debuggables')
end)

-- Explain errors
map("n", "<leader>ee", function()
    vim.cmd.RustLsp('explainError')
end)

-- Show error
map("n", "<leader>e", function()
    vim.cmd.RustLsp('renderDiagnostic')
end)

-- Update this path
local extension_path = dap_path

local codelldb_path = extension_path .. 'adapter/codelldb'
local liblldb_path = extension_path .. 'lldb/lib/liblldb'
local this_os = vim.uv.os_uname().sysname;

-- The path is different on Windows
if this_os:find "Windows" then
    codelldb_path = extension_path .. "adapter\\codelldb.exe"
    liblldb_path = extension_path .. "lldb\\bin\\liblldb.dll"
else
    -- The liblldb extension is .so for Linux and .dylib for MacOS
    liblldb_path = liblldb_path .. (this_os == "Linux" and ".so" or ".dylib")
end

local cfg = require('rustaceanvim.config')

vim.g.rustaceanvim = {
    -- Plugin configuration
    tools = {
    },
    -- LSP configuration
    server = {
        cmd = { "lspmux", "client", "--server-path", rust_analyzer_path },
        on_attach = function(client, bufnr)
            -- you can also put keymaps in here
        end,
        default_settings = {
            ["rust-analyzer"] = {
                files = {
                    excludeDirs = { ".direnv" },
                },
                cargo = {
                    --allFeatures = false,
                    loadOutDirsFromCheck = true,
                    buildScripts = {
                        enable = true,
                    },
                    runBuildScripts = true,
                },
                -- Add clippy/check lints for Rust.
                checkOnSave = true,
                check = {
                    command = "check",
                    allTargets = true,
                },
                procMacro = {
                    enable = true,
                    ignored = {
                        --            ["async-trait"] = { "async_trait" },
                        ["napi-derive"] = { "napi" },
                        ["async-recursion"] = { "async_recursion" },
                    },
                },
            },
        },
    },
    -- DAP configuration
    dap = {
        adapter = cfg.get_codelldb_adapter(codelldb_path, liblldb_path),
    },
}

dap.adapters.codelldb = {
  type = "executable",
  command = codelldb_path,
  -- On windows you may have to uncomment this:
  -- detached = false,
}

-- print dap_path
-- the adapters are setup according to https://github.com/mfussenegger/nvim-dap/wiki/Debug-Adapter-installation
--
--dap.adapters.lldb = {
--    name = 'lldb',
--    type = 'executable',
--    command = dap_path,
--}


require("dapui").setup()

local dapui = require("dapui")
dap.listeners.after.event_initialized["dapui_config"] = function()
    dapui.open()
end
dap.listeners.before.event_terminated["dapui_config"] = function()
    dapui.close()
end
dap.listeners.before.event_exited["dapui_config"] = function()
    dapui.close()
end

-- dap.configurations.rust = {
--     {
--         -- ... the previous config goes here ...,
--         name = 'Launch',
--         type = 'lldb',
--         request = 'launch',
--         program = function()
--             return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
--         end,
--         cwd = '${workspaceFolder}',
--         stopOnEntry = false,
--         args = {},
--         runInTerminal = false,
--         initCommands = function()
--             -- Find out where to look for the pretty printer Python module.
--             local rustc_sysroot = vim.fn.trim(vim.fn.system 'rustc --print sysroot')
--             assert(
--                 vim.v.shell_error == 0,
--                 'failed to get rust sysroot using `rustc --print sysroot`: '
--                 .. rustc_sysroot
--             )
--             local script_file = rustc_sysroot .. '/lib/rustlib/etc/lldb_lookup.py'
--             local commands_file = rustc_sysroot .. '/lib/rustlib/etc/lldb_commands'
-- 
--             -- The following is a table/list of lldb commands, which have a syntax
--             -- similar to shell commands.
--             --
--             -- To see which command options are supported, you can run these commands
--             -- in a shell:
--             --
--             --   * lldb --batch -o 'help command script import'
--             --   * lldb --batch -o 'help command source'
--             --
--             -- Commands prefixed with `?` are quiet on success (nothing is written to
--             -- debugger console if the command succeeds).
--             --
--             -- Prefixing a command with `!` enables error checking (if a command
--             -- prefixed with `!` fails, subsequent commands will not be run).
--             --
--             -- NOTE: it is possible to put these commands inside the ~/.lldbinit
--             -- config file instead, which would enable rust types globally for ALL
--             -- lldb sessions (i.e. including those run outside of nvim). However,
--             -- that may lead to conflicts when debugging other languages, as the type
--             -- formatters are merely regex-matched against type names. Also note that
--             -- .lldbinit doesn't support the `!` and `?` prefix shorthands.
--             return {
--                 ([[!command script import '%s']]):format(script_file),
--                 ([[command source '%s']]):format(commands_file),
--             }
--         end,
--         env = function()
--             local variables = {}
--             for k, v in pairs(vim.fn.environ()) do
--                 table.insert(variables, string.format("%s=%s", k, v))
--             end
--             return variables
--         end,
-- 
--         -- ...,
--     },
-- }

-- This is your opts table
require("telescope").setup {
    defaults = {
    },
    extensions = {
        ["ui-select"] = {
            require("telescope.themes").get_dropdown {
                -- even more opts
            },
        }
    }
}
-- To get ui-select loaded and working with telescope, you need to call
-- load_extension, somewhere after setup function:
require("telescope").load_extension("ui-select")


--dap.configurations.rust = {
--  {
--    -- ... the previous config goes here ...,
--    -- ...,
--  }
--}
