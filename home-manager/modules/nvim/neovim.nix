{ config, lib, pkgs, pkgs-unstable, pkgs-master, inputs, flakeRoot, ... }:
let
  inherit (pkgs) stdenv;
  jump = inputs.jump.packages.${pkgs.stdenv.hostPlatform.system}.default;
  servicePath = lib.concatStringsSep ":" (
    (config.home.sessionPath or [ ])
    ++ [
      "/etc/profiles/per-user/${config.home.username}/bin"
      "/run/wrappers/bin"
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
    nodejs_24
    go
    gopls
    gotools

    basedpyright
    ruff

    nixd

    # for toggling dark mode
    neovim-remote

    proximity-sort

    # for debugging
    lldb

    # for creating diagrams
    graphviz

    # bash lsp
    pkgs-unstable.bash-language-server
    shellcheck
    shfmt

    tree-sitter

    # protobuf support
    protols
    clang-tools # formatting is enabled when clang-format is available
    buf # buf format for proto files


    # node
    typescript
    typescript-language-server
    pkgs.prettier
    vscode-langservers-extracted
    eslint
    vtsls

    # lua
    lua-language-server
    stylua


    # nix
    nixfmt
    deadnix
    statix

    # yaml
    yaml-language-server

    # golang & terraform
    terraform
    terraform-ls

    actionlint
    gh
    pkgs-unstable.lspmux

    # https://github.com/mrcjkb/rustaceanvim?tab=readme-ov-file#using-codelldb-for-debugging
    vscode-extensions.vadimcn.vscode-lldb

    # for linux only
  ] ++ lib.optionals stdenv.hostPlatform.isLinux [
    # clipboard support for Wayland
    wl-clipboard
    # code navigation for hyprland/tmux/nvim workflow
    jump
  ];

  programs.neovim = {
    enable = true;
    # 26.05 flips these defaults to false; keep current behavior explicitly.
    withPython3 = true;
    withRuby = true;
    #package = pkgs-unstable.neovim-unwrapped;
    plugins = with pkgs.vimPlugins; [
      # VIM enhancments
      vim-sneak
      # base16-vim


      # GUI enhancments
      vim-matchup

      # Fuzzy searcher
      #vim-rooter
      fzf-vim

      tabular

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

      nvim-lspconfig

      # for vsnip users
      cmp-vsnip
      vim-vsnip
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      cmp-cmdline

      nvim-bqf
      telescope-nvim
      telescope-fzy-native-nvim
      # customize live grep
      telescope-live-grep-args-nvim

      # Tree viewer
      nvim-tree-lua

      gitsigns-nvim
      diffview-nvim
      octo-nvim
      trouble-nvim
      which-key-nvim

      rustaceanvim

      copilot-vim

      telescope-ui-select-nvim

      # flutter
      flutter-tools-nvim

      # scala 
      nvim-metals

      # notes plugins for obsidian
      obsidian-nvim

      conform-nvim
      nvim-lint
      SchemaStore-nvim


      # database access
      vim-dadbod
      vim-dadbod-completion
      vim-dadbod-ui


      # fast switching between marks:
      marks-nvim

      # git commands
      vim-fugitive

    ] ++ lib.optionals (pkgs.stdenv.hostPlatform.system != "aarch64-linux") [
      #vim-go
    ]
    ++ [
      # pkgs.unstable.vimPlugins
      nvim-treesitter.withAllGrammars
      nvim-treesitter-context
      nvim-treesitter-textobjects
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

    initLua =
      builtins.concatStringsSep "\n" [
        (builtins.readFile ./config/init.lua)
        (builtins.readFile ./config/databases.lua)
        (builtins.readFile ./config/lsp-config.lua)
        (builtins.readFile ./config/formatting.lua)
        (builtins.readFile ./config/git.lua)
        (builtins.readFile ./config/review.lua)
        (builtins.readFile ./config/treesitter.lua)
        "local dap_path  = \"${pkgs-unstable.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/\""
        (builtins.readFile ./config/rust-config.lua)
        "local metals_path = \"${pkgs-unstable.metals}/bin/metals\""
        (builtins.readFile ./config/metals-config.lua)
        (builtins.readFile ./config/obsidian.lua)
        (builtins.readFile ./config/protols.lua)
        (builtins.readFile ./config/node.lua)
        (builtins.readFile ./config/lua.lua)
        (builtins.readFile ./config/marks.lua)
        (builtins.readFile ./config/yaml.lua)
        (builtins.readFile ./config/diffview.lua)
        (builtins.readFile ./config/bash.lua)
        (builtins.readFile ./config/golang.lua)
        (builtins.readFile ./config/python.lua)
        (builtins.readFile ./config/html.lua)
        # do-block: the file ends with `return M`, which must be last in its chunk
        "do\n${builtins.readFile ./config/eink-bridge.lua}\nend"
      ];


  };


  #home.file."${config.home.homeDirectory}/.config/nvim/ftplugin/java.lua".source = config.lib.file.mkOutOfStoreSymlink ./config/ftplugin/java.lua;
  home.file."${config.home.homeDirectory}/.config/nvim/ftplugin/json.lua".source = config.lib.file.mkOutOfStoreSymlink ./config/ftplugin/json.lua;
  home.file."${config.home.homeDirectory}/.config/nvim/ftplugin/markdown.lua".source = config.lib.file.mkOutOfStoreSymlink ./config/ftplugin/markdown.lua;

  home.file."${config.home.homeDirectory}/.config/nvim/colors/sunlight.lua".source = config.lib.file.mkOutOfStoreSymlink "${flakeRoot}/home-manager/modules/nvim/config/colors/sunlight.lua";
  home.file."${config.home.homeDirectory}/.config/nvim/plugin/theme_cycle.lua".source = config.lib.file.mkOutOfStoreSymlink "${flakeRoot}/home-manager/modules/nvim/config/plugin/theme_cycle.lua";
  home.file."${config.home.homeDirectory}/.config/nvim/queries/rust/highlights.scm".source = config.lib.file.mkOutOfStoreSymlink "${flakeRoot}/home-manager/modules/nvim/config/queries/rust/highlights.scm";

  home.file."${config.home.homeDirectory}/.ideavimrc".source = config.lib.file.mkOutOfStoreSymlink ./config/idea-vim-config.vim;

  xdg.configFile."lspmux/config.toml".text = ''
    instance_timeout = 14400
    pass_environment = [
      "PATH",
      "LD_LIBRARY_PATH",
      "LIBRARY_PATH",
      "PKG_CONFIG_PATH",
      "PKG_CONFIG_LIBDIR",
      "PKG_CONFIG_SYSROOT_DIR",
      "CPATH",
      "C_INCLUDE_PATH",
      "CPLUS_INCLUDE_PATH",
      "CC",
      "CXX",
      "CFLAGS",
      "CXXFLAGS",
      "NIX_CFLAGS_COMPILE",
      "NIX_CFLAGS_COMPILE_FOR_TARGET",
      "NIX_CFLAGS_COMPILE_FOR_BUILD",
      "NIX_LDFLAGS",
      "NIX_LDFLAGS_FOR_TARGET",
      "RUSTFLAGS",
      "RUSTDOCFLAGS",
      "RUSTC_WRAPPER",
      "RUST_SRC_PATH",
      "CARGO_TARGET_DIR",
      "OPENSSL_DIR",
      "OPENSSL_LIB_DIR",
      "OPENSSL_INCLUDE_DIR",
      "LIBCLANG_PATH",
      "BINDGEN_EXTRA_CLANG_ARGS",
      "SSL_CERT_FILE",
      "NIX_SSL_CERT_FILE",
      "PROTOC",
      "PROTOC_INCLUDE",
    ]
  '';

  systemd.user.services."lspmux" = lib.mkIf stdenv.hostPlatform.isLinux {
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

  launchd.agents."lspmux" = lib.mkIf stdenv.hostPlatform.isDarwin {
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
