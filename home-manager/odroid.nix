{ config, lib, pkgs, ... }:

{
  imports = [
    ./modules/home-manager.nix
    ./modules/common.nix
    ./modules/nvim/neovim.nix
    ./modules/zsh.nix
    ./modules/tmux.nix

    ./modules/modivo.nix
  ];

  home = {
    username = "flakm";
    homeDirectory = "/home/flakm";
    stateVersion = "23.05";
  };


}
