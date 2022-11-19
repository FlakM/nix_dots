{ config, lib, pkgs, ... }:

{
  imports = [
    ./modules/home-manager.nix
    ./modules/common.nix
    ./modules/nvim/neovim.nix
    ./modules/rust.nix
    ./modules/zsh.nix
    ./modules/tmux.nix
    ./modules/alacritty.nix
    ./modules/git.nix
    ./modules/gpg.nix
    ./modules/brother.nix
  ];

  home = {
    stateVersion = "22.05";
  };


}
