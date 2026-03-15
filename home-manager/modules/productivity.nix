{ config, pkgs, pkgs-unstable, libs, lib, ... }:
{
  home.packages = with pkgs; [
    timewarrior
    pkgs.obsidian
    gcalcli
  ];

  programs.dircolors = {
    enable = true;
  };
}
