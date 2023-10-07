{ config, pkgs, pkgsUnstable, libs, ... }: {

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
  };

}
