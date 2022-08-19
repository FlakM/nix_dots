{ config, pkgs, pkgsUnstable, libs, ... }:
{

  home.packages = with pkgs; [
    _1password
  ];

}
