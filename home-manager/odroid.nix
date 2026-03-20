{ config, lib, pkgs, ... }:

{
  imports = [
    ./modules/home-manager.nix
    ./modules/common.nix
    ./modules/nvim/neovim.nix
    ./modules/zsh.nix
    ./modules/tmux.nix

    ./modules/atuin.nix
    ./modules/kitty.nix
    ./modules/starship.nix
    ./modules/pw-play-wrapper.nix
  ];

  home = {
    username = "flakm";
    homeDirectory = "/home/flakm";
    stateVersion = "23.05";
  };


}
