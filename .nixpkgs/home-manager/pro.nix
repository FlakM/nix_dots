{ config, lib, pkgs, ... }:

{
  imports = [
    ./modules/home-manager.nix
    ./modules/common.nix
    ./modules/nvim/neovim.nix
  ];


  home = {
    homeDirectory = "/Users/mflak";
    username = "mflak";
    stateVersion = "22.05";
  };




  programs.git.signing.signByDefault = true;

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "1password-cli"
  ];
}
