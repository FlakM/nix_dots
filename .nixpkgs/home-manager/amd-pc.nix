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
    ./modules/gpg.nix
    ./modules/brother.nix

    ./modules/alacritty.nix

    ./modules/i3.nix

    ./modules/modivo.nix
  ];

  home = {
    pointerCursor = {
      name = "Adwaita";
      package = pkgs.gnome.adwaita-icon-theme;
      size = 24;
      x11 = {
        enable = true;
        defaultCursor = "Adwaita";
      };
    };
    stateVersion = "22.11";
  };


}
