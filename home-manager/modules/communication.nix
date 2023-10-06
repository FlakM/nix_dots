{ config, pkgs, pkgsUnstable, libs, ... }:
{

  home.packages = with pkgs; [
    mumble
    unstable.teams-for-linux
    google-chrome
  ];

}


