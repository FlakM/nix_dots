{ pkgs, inputs, lib, pkgs-unstable, pkgs-master, config, ... }:
{




  system.stateVersion = 5;

  services.nix-daemon.enable = true;
  services.karabiner-elements.enable = true;

  environment.systemPackages = with pkgs; [
    bat
    home-manager


    rustup
  ];



  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" ]; })
  ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
  };

  environment.shells = with pkgs; [
    zsh bashInteractive
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

}

