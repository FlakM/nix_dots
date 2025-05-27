{ config, pkgs, pkgs-master, libs, ... }:
{

  home.packages = [
    pkgs-master.dbeaver-bin
  ];

}
