{ config, pkgs, libs, ... }:
{
  programs.home-manager.enable = true;
  programs.zsh.enable = true;
  systemd.user.startServices = "sd-switch";
}
