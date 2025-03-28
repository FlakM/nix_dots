local map = vim.keymap.set
local dap = require('dap')

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



vim.g.rustaceanvim = {
    -- Plugin configuration
    tools = {
    },
    -- LSP configuration
    server = {
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
                checkOnSave = {
                    enable = true,
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
    },
}



-- print dap_path
-- the adapters are setup according to https://github.com/mfussenegger/nvim-dap/wiki/Debug-Adapter-installation
--
dap.adapters.lldb = {
    name = 'lldb',
    type = 'executable',
    command = dap_path,
}


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

dap.configurations.rust = {
    {
        name = 'Launch',
        type = 'lldb',
        request = 'launch',
        program = function()
            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
        args = {},
        initCommands = function()
            -- Find out where to look for the pretty printer Python module
            local rustc_sysroot = vim.fn.trim(vim.fn.system('rustc --print sysroot'))

            local script_import = 'command script import "' .. rustc_sysroot .. '/lib/rustlib/etc/lldb_lookup.py"'
            local commands_file = rustc_sysroot .. '/lib/rustlib/etc/lldb_commands'

            local commands = {}
            local file = io.open(commands_file, 'r')
            if file then
                for line in file:lines() do
                    table.insert(commands, line)
                end
                file:close()
            end
            table.insert(commands, 1, script_import)

            return commands
        end,

        -- gather the environment variables from the shell
        env = function()
            local variables = {}
            for k, v in pairs(vim.fn.environ()) do
                table.insert(variables, string.format("%s=%s", k, v))
            end
            return variables
        end,
        -- 💀
        -- if you change `runInTerminal` to true, you might need to change the yama/ptrace_scope setting:
        --
        --    echo 0 | sudo tee /proc/sys/kernel/yama/ptrace_scope
        --
        -- Otherwise you might get the following error:
        --
        --    Error on launch: Failed to attach to the target process
        --
        -- But you should be aware of the implications:
        -- https://www.kernel.org/doc/html/latest/admin-guide/LSM/Yama.html
        -- runInTerminal = false,
    },
}

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
