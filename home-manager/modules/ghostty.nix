{ config, pkgs, pkgs-unstable, lib, ... }:
{


  programs.ghostty = {
    enable = true;
    installVimSyntax = true;
    enableZshIntegration = true;
    installBatSyntax = true;
    clearDefaultKeybinds = true;

    settings = {
      theme = "dark:Mathias,light:3024 Day";
      gtk-titlebar = false;
      macos-titlebar-style = "hidden";
    };
  };
}
