{ pkgs, inputs, lib, pkgs-unstable, pkgs-master, config, ... }:
{


  system.stateVersion = 5;
  system.primaryUser = "flakm";

  services.karabiner-elements.enable = true;

  environment.systemPackages = with pkgs; [
    bat
    home-manager


    rustup
  ];


  fonts.packages =  [
    pkgs.nerd-fonts.fira-code
  ];


  programs.zsh = {
    enable = true;
    enableCompletion = true;
  };

  environment.shells = with pkgs; [
    zsh
    bashInteractive
  ];


  users.users.maciek = {
    home = "/Users/maciek";
    shell = pkgs.zsh;
    uid = 502;
  };

  users.knownUsers = [
    "maciek"
  ];


  environment.pathsToLink = [ "/share/zsh" ];



  services.tailscale.enable = true;


  #system.activationScripts.postUserActivation.text = ''
  #  rsyncArgs="--archive --checksum --chmod=-w --copy-unsafe-links --delete"
  #  apps_source="${config.system.build.applications}/Applications"
  #  moniker="Nix Trampolines"
  #  app_target_base="$HOME/Applications"
  #  app_target="$app_target_base/$moniker"
  #  mkdir -p "$app_target"
  #  # shellcheck disable=SC2086
  #  ${pkgs.rsync}/bin/rsync $rsyncArgs "$apps_source/" "$app_target"
  #'';

}

