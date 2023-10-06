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
    ./modules/yubikey.nix
  ];


  home = {
    username = "flakm";
    homeDirectory = "/home/flakm";
    stateVersion = "23.05";
  };


}
