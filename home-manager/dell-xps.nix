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

    ./modules/modivo.nix
    ./modules/yubikey.nix


    ./modules/communication.nix


    ./modules/firefox.nix
    ./modules/productivity.nix

    ./modules/neomutt.nix
    ./modules/hyprland.nix

    ./modules/atuin.nix
    ./modules/kitty.nix
    ./modules/starship.nix
  ];


  wayland.windowManager.hyprland.settings = {
    # Monitor settings
    monitor = ",highres,auto,2.0";
  };

  programs.alacritty.settings.font.size = 11;

  xdg.enable = true;

  gtk = {
    enable = true;
    theme = {
      package = pkgs.gnome.gnome-themes-extra;
      name = "Adwaita";
    };
    iconTheme = {
      package = pkgs.gnome.adwaita-icon-theme;
      name = "Adwaita";
    };
    font = {
      name = "Sans";
      size = 11;
    };
  };

  home = {
    username = "flakm";
    homeDirectory = "/home/flakm";
    pointerCursor = {
      gtk.enable = true;
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Amber";
      size = 24;
    };
    stateVersion = "23.05";



  };


}
