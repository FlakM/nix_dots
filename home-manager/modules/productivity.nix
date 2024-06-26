{ config, pkgs, pkgs-unstable, libs, lib, ... }:
{
  nixpkgs.config.permittedInsecurePackages =
    lib.optional (pkgs.obsidian.version == "1.4.16") "electron-25.9.0";


  home.packages = with pkgs; [
    timewarrior
    pkgs.obsidian
  ];

  programs.dircolors = {
    enable = true;
  };
}
