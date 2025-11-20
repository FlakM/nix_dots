{ config, lib, pkgs, pkgs-unstable, pkgs-master, ... }:
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
  servicePath = lib.concatStringsSep ":" (
    (config.home.sessionPath or [])
    ++ [
      "${config.home.homeDirectory}/.nix-profile/bin"
      "/run/wrappers/bin"
      "/etc/profiles/per-user/${config.home.username}/bin"
      "/nix/var/nix/profiles/default/bin"
      "/run/current-system/sw/bin"
    ]
  );
in
{
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    #NVIM_LISTEN_ADDRESS = "/tmp/nvimsocket";
  };

  home.packages = with pkgs; [
    # for copilot
    nodejs
    go
    gopls

    pyright

    nil

    # for toggling dark mode
    neovim-remote

    # for debugging
    python3

    proximity-sort

    # for debugging
    lldb

    # for creating diagrams
    graphviz

    # bash lsp
    pkgs-unstable.nodePackages.bash-language-server
    shfmt

    tree-sitter

    # protobuf support
    protols
    clang-tools # formatting is enabled when clang-format is available
    buf # buf format for proto files


    # node
    typescript
    typescript-language-server
    nodePackages.prettier
    vscode-langservers-extracted
    eslint

    # lua
    lua-language-server


    # nix
    nixpkgs-fmt

    # yaml
    #yaml-language-server

    # golang & terraform
    gopls
    terraform-lsp

    # https://github.com/mrcjkb/rustaceanvim?tab=readme-ov-file#using-codelldb-for-debugging
    vscode-extensions.vadimcn.vscode-lldb

    # for linux only
  ] ++ lib.optionals stdenv.isLinux [
    # for debugging
    bashdb
    # clipboard support for Wayland
    wl-clipboard
    pkgs-unstable.lspmux
  ];

  programs.neovim = {
    enable = true;
    #package = pkgs-unstable.neovim-unwrapped;
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
      edge

      vim-one


      #vim-nightfly-guicolors
      lualine-nvim
      nvim-web-devicons

      # LSP support & completion
      plenary-nvim
      nvim-dap
      nvim-dap-ui
      nvim-nio

      fidget-nvim

      git-blame-nvim

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
      # customize live grep
      telescope-live-grep-args-nvim

      # Tree viewer
      nvim-tree-lua

      vim-gitgutter

      rustaceanvim

      copilot-vim

      telescope-ui-select-nvim

      # flutter
      flutter-tools-nvim

      # scala 
      nvim-metals

      # notes plugins for obsidian
      obsidian-nvim

      none-ls-nvim
      lsp_lines-nvim


      # database access
      vim-dadbod
      vim-dadbod-completion
      vim-dadbod-ui


      # fast switching between marks:
      marks-nvim

      # copy to clipboard git links
      vim-fugitive
      vim-rhubarb


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
    extraPackages = with pkgs; [
      # for debugging
      clang
    ];


    extraLuaConfig =
      builtins.concatStringsSep "\n" [
        (builtins.readFile ./config/init.lua)
        (builtins.readFile ./config/databases.lua)
        (builtins.readFile ./config/lsp-config.lua)
        "local dap_path  = \"${pkgs-unstable.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/\""
        (builtins.readFile ./config/rust-config.lua)
        "local metals_path = \"${pkgs-unstable.metals}/bin/metals\""
        (builtins.readFile ./config/metals-config.lua)
        (builtins.readFile ./config/obsidian.lua)
        (builtins.readFile ./config/protols.lua)
        (builtins.readFile ./config/node.lua)
        (builtins.readFile ./config/lua.lua)
        (builtins.readFile ./config/marks.lua)
        #(builtins.readFile ./config/yaml.lua)
        (builtins.readFile ./config/git.lua)
        (if stdenv.isLinux then
          "local bashdb_path = \"${pkgs.bashdb}/bin/bashdb\""
        else
          "local bashdb_path = nil")
        (builtins.readFile ./config/bash.lua)
        (builtins.readFile ./config/golang.lua)
        (builtins.readFile ./config/python.lua)
      ];


  };


  #home.file."${config.home.homeDirectory}/.config/nvim/ftplugin/java.lua".source = config.lib.file.mkOutOfStoreSymlink ./config/ftplugin/java.lua;
  home.file."${config.home.homeDirectory}/.config/nvim/ftplugin/json.lua".source = config.lib.file.mkOutOfStoreSymlink ./config/ftplugin/json.lua;
  home.file."${config.home.homeDirectory}/.config/nvim/ftplugin/markdown.lua".source = config.lib.file.mkOutOfStoreSymlink ./config/ftplugin/markdown.lua;

  home.file."${config.home.homeDirectory}/.ideavimrc".source = config.lib.file.mkOutOfStoreSymlink ./config/idea-vim-config.vim;

  systemd.user.services."lspmux" = lib.mkIf stdenv.isLinux {
    Unit = {
      Description = "lspmux rust-analyzer multiplexer";
      After = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "${pkgs-unstable.lspmux}/bin/lspmux server";
      Restart = "on-failure";
      RestartSec = 2;
      Environment = [
        "RUST_LOG=info"
        "PATH=${servicePath}"
      ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  launchd.agents."lspmux" = lib.mkIf stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs-unstable.lspmux}/bin/lspmux"
        "server"
      ];
      KeepAlive = true;
      RunAtLoad = true;
      EnvironmentVariables = {
        RUST_LOG = "info";
        PATH = servicePath;
      };
    };
  };
}
