{ config, lib, pkgs, pkgs-unstable, ... }:
let
  inherit (pkgs) stdenv;
  nvim-dap-probe-rs = pkgs.vimUtils.buildVimPlugin {
    name = "nvim-dap-probe-rs";
    src = pkgs.fetchFromGitHub {
      owner = "abayomi185";
      repo = "nvim-dap-probe-rs";
      rev = "6df52c49755d78a2d7754c0630dd58694ea39ada";
      hash = "sha256-SVEJG+2oVqJKaH4+jDp2ZpbJIWIL4nqGkH0cN9pCa6M=";
    };
  };
in
{
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    NVIM_LISTEN_ADDRESS = "/tmp/nvimsocket";
  };

  home.packages = with pkgs; [
    # for copilot
    nodejs
    go
    gopls

    nil

    # for toggling dark mode
    neovim-remote

    # for debugging
    python3

    proximity-sort

    # for debugging
    lldb

    # bash lsp
    pkgs-unstable.nodePackages.bash-language-server
    shfmt

    # for linux only
  ] ++ lib.optionals stdenv.isLinux [
    # for debugging
    bashdb
  ];

  programs.neovim = {
    enable = true;
    package = pkgs-unstable.neovim-unwrapped;
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
      pkgs-unstable.vimPlugins.material-nvim
      pkgs-unstable.vimPlugins.edge


      #vim-nightfly-guicolors
      lualine-nvim
      nvim-web-devicons

      # LSP support & completion
      plenary-nvim
      pkgs-unstable.vimPlugins.nvim-dap
      pkgs-unstable.vimPlugins.nvim-dap-ui
      pkgs-unstable.vimPlugins.nvim-nio

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

      pkgs-unstable.vimPlugins.rustaceanvim

      one-nvim

      copilot-vim

      telescope-ui-select-nvim

      # flutter
      flutter-tools-nvim

      # scala 
      nvim-metals

      # notes plugins for obsidian
      obsidian-nvim




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
        "local dap_path  = \"${pkgs.lldb}/bin/lldb-vscode\""
        (builtins.readFile ./config/rust-config.lua)
        "EOF"

        "lua << EOF"
        "local metals_path = \"${pkgs-unstable.metals}/bin/metals\""
        (builtins.readFile ./config/metals-config.lua)
        (builtins.readFile ./config/obsidian.lua)

        (if stdenv.isLinux then
          "local bashdb_path = \"${pkgs.bashdb}/bin/bashdb\""
        else
          "local bashdb_path = nil")

        (builtins.readFile ./config/bash.lua)



        # of on linux
        

        #(builtins.readFile ./config/python-config.vim)
        #(builtins.readFile ./config/go-config.vim)
      ]

      );


  };


  #home.file."${config.home.homeDirectory}/.config/nvim/ftplugin/java.lua".source = config.lib.file.mkOutOfStoreSymlink ./config/ftplugin/java.lua;
  home.file."${config.home.homeDirectory}/.config/nvim/ftplugin/json.lua".source = config.lib.file.mkOutOfStoreSymlink ./config/ftplugin/json.lua;
  home.file."${config.home.homeDirectory}/.config/nvim/ftplugin/makrdown.lua".source = config.lib.file.mkOutOfStoreSymlink ./config/ftplugin/markdown.lua;

  home.file."${config.home.homeDirectory}/.ideavimrc".source = config.lib.file.mkOutOfStoreSymlink ./config/idea-vim-config.vim;
}

