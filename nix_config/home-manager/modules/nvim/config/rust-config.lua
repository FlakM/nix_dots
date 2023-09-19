local codelldb_path = extension_path .. '/adapter/codelldb'
local liblldb_path = extension_path .. '/lldb/lib/liblldb.so'  -- MacOS: This may be .dylib

local rt = require("rust-tools")

rt.setup({
  tools = {
    runnables = {
    	use_telescope = true,
    },
    debuggables = {
    	use_telescope = true,
    },
  },
  server = {
    settings = {
      ['rust-analyzer'] = {
        checkOnSave = {
            -- this shows clippy warnings alongside rustc warnings
            command = "clippy"
        },
      }
    },
    on_attach = function(_, bufnr)
      -- Hover actions
      vim.keymap.set("n", "<C-space>", rt.hover_actions.hover_actions, { buffer = bufnr })
      -- Code action groups
      vim.keymap.set("n", "<Leader>a", rt.code_action_group.code_action_group, { buffer = bufnr })
    end,
  },
  dap = {
      -- this sets the path to the codelldb-vscode extension_path
      -- it adds nice debug information about the types like String
      -- the library is downloaded by neovim.nix: and its called vscode-extensions.vadimcn.vscode-lldb
      -- and the `extension_path` is injected in `extraConfig` section
      -- https://github.com/simrat39/rust-tools.nvim/wiki/Debugging#codelldb-a-better-debugging-experience
      adapter = require('rust-tools.dap').get_codelldb_adapter(
          codelldb_path, liblldb_path)
  },
})

require("dapui").setup()

local dap, dapui = require("dap"), require("dapui")
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
    -- ... the previous config goes here ...,
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
    -- ...,
  }
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
