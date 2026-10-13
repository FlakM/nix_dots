{ config, pkgs, lib, ... }:
{
  programs.home-manager.enable = true;
  programs.zsh.enable = true;
  systemd.user.startServices = lib.mkIf pkgs.stdenv.hostPlatform.isLinux "sd-switch";
}
