{ config, lib, pkgs, ... }:
{
  home.sessionVariables = {
     EDITOR = "nvim";
  };

  home.packages = with pkgs; [
    # for copilot
    nodejs-16_x
    go
    gopls
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

      #Theme
      material-nvim
      #vim-nightfly-guicolors
      lualine-nvim
      nvim-web-devicons

      # LSP support & completion
      plenary-nvim
      nvim-metals
      nvim-dap
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
      nvim-treesitter
      telescope-nvim
      telescope-fzy-native-nvim

      # Tree viewer
      nvim-tree-lua

      vim-gitgutter

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
    ];

    extraConfig = (builtins.concatStringsSep "\n" [
      (builtins.readFile ./config/init.vim)
      # this is a hack because pyright installed from brew also brings node but in version 18 into scope
      # and copilot stops working so in this way we tell copilot where the valid version of node is
      """
      let g:copilot_node_command = '${pkgs.nodejs-16_x}/bin/node'
      """
      (builtins.readFile ./config/lsp-config.vim)
      """
lua << EOF
      custom = {
        java = '${pkgs.jdk}/bin/java';
        jar = '${pkgs.jdt-language-server}/share/java/plugins/org.eclipse.equinox.launcher_1.6.400.v20210924-0641.jar',
        configuration = '${pkgs.jdt-language-server}/share/config/config.ini', 
        home = '${config.home.homeDirectory}/',
}
EOF
      """
      (builtins.readFile ./config/rust-config.vim)
      (builtins.readFile ./config/metals-config.vim)
      (builtins.readFile ./config/python-config.vim)
      (builtins.readFile ./config/go-config.vim)
    ]);
  };

  home.file."${config.home.homeDirectory}/.config/nvim/ftplugin/java.lua".source = config.lib.file.mkOutOfStoreSymlink ./config/java.lua;
  home.file."${config.home.homeDirectory}/.ideavimrc".source = config.lib.file.mkOutOfStoreSymlink ./config/idea-vim-config.vim;
}
