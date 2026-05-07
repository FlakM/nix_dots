{ pkgs, inputs, lib, pkgs-unstable, pkgs-master, config, ... }:
{


  system.stateVersion = 5;
  services.karabiner-elements.enable = true;

  environment.systemPackages = with pkgs; [
    bat
    home-manager


    rustup
  ];


  fonts.packages = [
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


  # The previous home-manager generations created a root-owned ~/Applications/Home
  # Manager Apps/ with symlinks into /nix/store. linkApps is now disabled, but the
  # stale directory persists and Launch Services keeps re-registering the store
  # paths from it. Remove it as root on each system activation.
  system.activationScripts.extraActivation.text = ''
    rm -rf "/Users/maciek/Applications/Home Manager Apps"
  '';

}
