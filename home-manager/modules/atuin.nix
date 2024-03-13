{ pkgs-unstable, ... }:
{
  # to address a slow startup sometimes
  # go to https://github.com/atuinsh/atuin/issues/952 
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    package = pkgs-unstable.atuin;
  };

}
