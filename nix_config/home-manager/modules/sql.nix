{ config, pkgs, pkgsUnstable, libs, ... }:
{

  home.packages = with pkgs; [
    dbeaver
  ];

}