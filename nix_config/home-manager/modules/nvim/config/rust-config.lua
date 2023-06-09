local codelldb_path = extension_path .. '/adapter/codelldb'
local liblldb_path = extension_path .. '/lldb/lib/liblldb.so'  -- MacOS: This may be .dylib

local rt = require("rust-tools")

rt.setup({
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


