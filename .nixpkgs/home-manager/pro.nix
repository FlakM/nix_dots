{ config, lib, pkgs, ... }:

{
  imports = [
    ./modules/home-manager.nix
    ./modules/common.nix
    ./modules/nvim/neovim.nix
    ./modules/tmux.nix
    ./modules/alacritty.nix
    ./modules/git.nix
    ./modules/scala.nix
    #./modules/gpg.nix
  ];

  home = {
    stateVersion = "22.05";
  };





  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "1password-cli"
  ];
}
