{ config, lib, pkgs, ... }:

{
  imports = [
    #./modules/home-manager.nix
    #./modules/common.nix
  ];


  home = {
    username = "maciek";
    homeDirectory = "/Users/maciek";
    stateVersion = "24.05";
  };

}
