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
    ./modules/scala.nix
    ./modules/gpg.nix
    ./modules/java.nix
    ./modules/aws.nix
    #./modules/1password.nix
  ];

  home = {
    stateVersion = "22.05";
  };


}
