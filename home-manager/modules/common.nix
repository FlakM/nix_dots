{ config, pkgs, pkgs-unstable, libs, lib, ... }:
{

  # https://github.com/nix-community/nix-direnv#via-home-manager
  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;


  home.packages = with pkgs; [
    jq
    wget
    curl
    unzip
    zip

    xsel

    bat
    fd
    ripgrep
    fzf
    htop
    dnsutils

    pkgs-unstable.yt-dlp
  ] ++ lib.optionals stdenv.isDarwin [
    coreutils # provides `dd` with --status=progress
  ] ++ lib.optionals stdenv.isLinux [
    iputils # provides `ping`, `ifconfig`, ...
    libuuid # `uuidgen` (already pre-installed on mac)
  ];

  programs.dircolors = {
    enable = true;
  };
}
