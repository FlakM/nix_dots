
{ config, pkgs, pkgs-unstable, libs, lib, ... }:
{
  home.packages = with pkgs; [
    pnpm
  ];
}
