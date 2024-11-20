-- confugured according to 
-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md#bashls
--
require'lspconfig'.bashls.setup{}


if bashdb_path ~= nil then
    local dap = require('dap')
    
    
    dap.adapters.bashdb = {
      type = 'executable';
      -- TODO this does not work since bash-debug-adapter is not packaged
      -- see https://github.com/NixOS/nixpkgs/issues/222711
      command = vim.fn.stdpath("data") .. '/mason/packages/bash-debug-adapter/bash-debug-adapter';
      name = 'bashdb';
    }
    
    
    dap.configurations.sh = {
      {
        type = 'bashdb';
        request = 'launch';
        name = "Launch file";
        showDebugOutput = true;
        pathBashdb = bashdb_path;
        --pathBashdbLib = vim.fn.stdpath("data") .. '/mason/packages/bash-debug-adapter/extension/bashdb_dir';
        trace = true;
        file = "${file}";
        program = "${file}";
        cwd = '${workspaceFolder}';
        pathCat = "cat";
        pathBash = "/bin/bash";
        pathMkfifo = "mkfifo";
        pathPkill = "pkill";
        args = {};
        env = {};
        terminalKind = "integrated";
      }
    }
end

