{ config, lib, pkgs, ... }:
{
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  home.packages = with pkgs; [
    # for copilot
    nodejs-16_x
    go
    gopls
    vscode-extensions.vadimcn.vscode-lldb
    nil
  ];

  programs.neovim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [
      # VIM enhancments
      editorconfig-vim
      vim-sneak
      # base16-vim


      # GUI enhancments
      vim-matchup

      # Fuzzy searcher
      #vim-rooter
      fzf-vim

      # Synctactic language support
      vim-toml
      vim-yaml
      rust-vim
      tabular
      vim-nix
      vim-terraform

      #Theme
      material-nvim
      #vim-nightfly-guicolors
      lualine-nvim
      nvim-web-devicons

      # LSP support & completion
      plenary-nvim
      nvim-dap
      nvim-dap-ui


      nvim-lspconfig

      # for vsnip users
      cmp-vsnip
      vim-vsnip
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      cmp-cmdline
      nvim-cmp

      nvim-bqf
      telescope-nvim
      telescope-fzy-native-nvim

      # Tree viewer
      nvim-tree-lua

      vim-gitgutter

      nvim-metals
      nvim-lspconfig
      rust-tools-nvim

      gruvbox-nvim
      papercolor-theme

      copilot-vim

      # java tols
      nvim-jdtls

      # handlebars support
      vim-mustache-handlebars

    ] ++ lib.optionals (pkgs.stdenv.system != "aarch64-linux") [
      #vim-go
    ]
    ++ [
      # pkgs.unstable.vimPlugins
      nvim-treesitter.withAllGrammars
      #nvim-treesitter
      #(nvim-treesitter.withPlugins (plugins: [
      #  plugins.tree-sitter-c
      #  plugins.tree-sitter-rust
      #  plugins.tree-sitter-scala
      #  plugins.tree-sitter-java
      #  plugins.tree-sitter-json
      #  plugins.tree-sitter-python
      #  plugins.tree-sitter-go
      #]))
    ];


    extraConfig =
      (builtins.concatStringsSep "\n" [
        "lua << EOF"
        (builtins.readFile ./config/init.lua)

        "EOF"
        (builtins.readFile ./config/init.vim)
        ""
        (builtins.readFile ./config/lsp-config.vim)
        ""
        ""
        "lua << EOF"
        "local extension_path = \"${pkgs.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb\""
        (builtins.readFile ./config/rust-config.lua)
        "EOF"

        (builtins.readFile ./config/metals-config.vim)
        #(builtins.readFile ./config/python-config.vim)
        #(builtins.readFile ./config/go-config.vim)
      ]);
  };


  #home.file."${config.home.homeDirectory}/.config/nvim/ftplugin/java.lua".source = config.lib.file.mkOutOfStoreSymlink ./config/ftplugin/java.lua;
  home.file."${config.home.homeDirectory}/.config/nvim/ftplugin/json.lua".source = config.lib.file.mkOutOfStoreSymlink ./config/ftplugin/json.lua;

  home.file."${config.home.homeDirectory}/.ideavimrc".source = config.lib.file.mkOutOfStoreSymlink ./config/idea-vim-config.vim;
}

