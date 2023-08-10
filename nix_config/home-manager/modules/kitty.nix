{ config, pkgs, pkgsUnstable, libs, ... }:
{

  programs.kitty = {
    enable = true;
    shellIntegration.enableZshIntegration = true;
  };
}

