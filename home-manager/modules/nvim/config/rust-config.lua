local dap = require('dap')

-- print extension_path
print(extension_path)


-- the adapters are setup according to https://github.com/mfussenegger/nvim-dap/wiki/Debug-Adapter-installation
--
dap.adapters.cppdbg = {
  id = 'cppdbg',
  type = 'executable',
  command = extension_path .. '/extension/debugAdapters/bin/OpenDebugAD7',
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

dap.configurations.cpp = {
  {
    name = "Launch file",
    type = "cppdbg",
    request = "launch",
    program = function()
      return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
    end,
    cwd = '${workspaceFolder}',
    stopAtEntry = true,
    setupCommands = {  
      { 
         text = '-enable-pretty-printing',
         description =  'enable pretty printing',
         ignoreFailures = false 
      },
    },
  },
  {
    name = 'Attach to gdbserver :1234',
    type = 'cppdbg',
    request = 'launch',
    MIMode = 'gdb',
    miDebuggerServerAddress = 'localhost:1234',
    miDebuggerPath = 'gdb',
    cwd = '${workspaceFolder}',
    program = function()
      return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
    end,
    setupCommands = {  
      { 
         text = '-enable-pretty-printing',
         description =  'enable pretty printing',
         ignoreFailures = false 
      },
    },
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

dap.configurations.c = dap.configurations.cpp
dap.configurations.rust = dap.configurations.cpp


dap.adapters["probe-rs-debug"] = {
  type = "server",
  port = "${port}",
  executable = {
    command = vim.fn.expand "probe-rs",
    args = { "dap-server", "--port", "${port}" },
  },
}
-- Connect the probe-rs-debug with rust files. Configuration of the debugger is done via project_folder/.vscode/launch.json
require("dap.ext.vscode").type_to_filetypes["probe-rs-debug"] = { "rust" }
-- Set up of handlers for RTT and probe-rs messages.
-- In addition to nvim-dap-ui I write messages to a probe-rs.log in project folder
-- If RTT is enabled, probe-rs sends an event after init of a channel. This has to be confirmed or otherwise probe-rs wont sent the rtt data.
dap.listeners.before["event_probe-rs-rtt-channel-config"]["plugins.nvim-dap-probe-rs"] = function(session, body)
  local utils = require "dap.utils"
  utils.notify(
    string.format('probe-rs: Opening RTT channel %d with name "%s"!', body.channelNumber, body.channelName)
  )
  local file = io.open("probe-rs.log", "a")
  if file then
    file:write(
      string.format(
        '%s: Opening RTT channel %d with name "%s"!\n',
        os.date "%Y-%m-%d-T%H:%M:%S",
        body.channelNumber,
        body.channelName
      )
    )
  end
  if file then file:close() end
  session:request("rttWindowOpened", { body.channelNumber, true })
end
-- After confirming RTT window is open, we will get rtt-data-events.
-- I print them to the dap-repl, which is one way and not separated.
-- If you have better ideas, let me know.
dap.listeners.before["event_probe-rs-rtt-data"]["plugins.nvim-dap-probe-rs"] = function(_, body)
  local message =
    string.format("%s: RTT-Channel %d - Message: %s", os.date "%Y-%m-%d-T%H:%M:%S", body.channelNumber, body.data)
  local repl = require "dap.repl"
  repl.append(message)
  local file = io.open("probe-rs.log", "a")
  if file then file:write(message) end
  if file then file:close() end
end
-- Probe-rs can send messages, which are handled with this listener.
dap.listeners.before["event_probe-rs-show-message"]["plugins.nvim-dap-probe-rs"] = function(_, body)
  local message = string.format("%s: probe-rs message: %s", os.date "%Y-%m-%d-T%H:%M:%S", body.message)
  local repl = require "dap.repl"
  repl.append(message)
  local file = io.open("probe-rs.log", "a")
  if file then file:write(message) end
  if file then file:close() end
end


