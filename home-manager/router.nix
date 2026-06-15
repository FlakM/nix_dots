{ pkgs, ... }:

{
  imports = [
    ./modules/home-manager.nix
    ./modules/zsh.nix
    ./modules/tmux.nix
    ./modules/starship.nix
  ];

  home = {
    username = "flakm";
    homeDirectory = "/home/flakm";
    stateVersion = "26.05";
    packages = with pkgs; [
      curl
      jq
      ripgrep
    ];
  };
}
