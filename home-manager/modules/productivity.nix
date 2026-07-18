{ config, pkgs, pkgs-unstable, libs, lib, ... }:
{
  home.packages = with pkgs; [
    timewarrior
    pkgs.obsidian
    gcalcli
    gws
    google-cloud-sdk
  ];

  programs.dircolors = {
    enable = true;
  };
}
