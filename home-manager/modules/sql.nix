{ config, pkgs, pkgs-master, libs, ... }:
{

  home.packages = [
    pkgs-master.dbeaver
    pkgs.pgadmin4-desktopmode
  ];

}
