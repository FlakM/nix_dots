{ config, pkgs, pkgs-unstable, lib, inputs, ... }:
{

  programs.ghostty = {
    enable = true;
    installVimSyntax = true;
    enableZshIntegration = true;
    installBatSyntax = true;
    clearDefaultKeybinds = true;
    #package = inputs.ghostty.packages.${pkgs.system}.default;

    settings = {
      theme = "dark:Mathias,light:3024 Day";
      gtk-titlebar = false;
      macos-titlebar-style = "hidden";
    };
  };
}
