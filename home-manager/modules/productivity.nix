{ config, pkgs, pkgsUnstable, libs, lib, ... }:
{


  home.packages = with pkgs; [
    timewarrior
    unstable.obsidian
  ];

  programs.dircolors = {
    enable = true;
  };
}
