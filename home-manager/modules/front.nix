{ config, pkgs, pkgs-unstable, libs, lib, ... }:
{
  home.packages = with pkgs; [
    pnpm
  ];

  home.sessionVariables = {
    LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.libuuid ] + "\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}";
  };
}
