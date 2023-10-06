{ config, pkgs, pkgsUnstable, libs, ... }:
{

  home.packages = with pkgs; [
    jdt-language-server
    gradle
    jdk
  ];
  programs.java = {
    enable = true;
  };
}
