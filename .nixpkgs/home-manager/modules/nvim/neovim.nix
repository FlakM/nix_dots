{ config, lib, pkgs, ... }:
{
  home.sessionVariables = {
     EDITOR = "nvim";
  };

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
      vim-rooter
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
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      cmp-cmdline
      nvim-cmp

      # for vsnip users
      cmp-vsnip
      vim-vsnip
      nvim-cmp
      cmp-nvim-lsp
  
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

    ] ++ lib.optionals (pkgs.stdenv.system != "aarch64-linux") [
      #vim-go
    ];

    extraConfig = (builtins.concatStringsSep "\n" [
      (builtins.readFile ./config/init.vim)
      (builtins.readFile ./config/lsp-config.vim)
      (builtins.readFile ./config/metals-config.vim)
      (builtins.readFile ./config/rust-config.vim)

    ]);
  };
}
