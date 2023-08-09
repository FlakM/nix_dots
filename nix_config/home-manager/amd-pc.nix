{ config, lib, pkgs, ... }:

{
  imports = [
    ./modules/home-manager.nix
    ./modules/common.nix
    ./modules/nvim/neovim.nix
    ./modules/rust.nix
    ./modules/zsh.nix
    ./modules/tmux.nix
    ./modules/git.nix
    ./modules/gpg_home.nix
    ./modules/brother.nix

    ./modules/alacritty.nix

    ./modules/modivo.nix
    ./modules/yubikey.nix


    ./modules/communication.nix

    ./modules/sql.nix
  ];



  xsession.windowManager.i3.config.fonts.size = 18.0;
  programs.alacritty.settings.font.size = 11;

  home = {
    username = "flakm";
    homeDirectory = "/home/flakm";
    pointerCursor = {
      name = "Adwaita";
      package = pkgs.gnome.adwaita-icon-theme;
      size = 24;
      x11 = {
        enable = true;
        defaultCursor = "Adwaita";
      };
    };
    stateVersion = "23.05";
  };


}