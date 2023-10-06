{ config, pkgs, libs, ... }:
{

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
  programs.zsh.enable = true;

  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = (_: true);
  };

  # Nicely reload system units when changing
  systemd.user.startServices = "sd-switch";
}
