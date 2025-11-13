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


    bat
    fd
    ripgrep
    fzf
    btop
    dnsutils

    neofetch

    pkgs-unstable.yt-dlp


    du-dust

    # tools for debugging grpc services
    grpcurl
    grpc-client-cli

    gnuplot
  ] ++ lib.optionals stdenv.isDarwin [
    coreutils-full # provides `dd` with --status=progress
  ] ++ lib.optionals stdenv.isLinux [
    iputils # provides `ping`, `ifconfig`, ...
    libuuid # `uuidgen` (already pre-installed on mac)
  ];

  programs.dircolors = {
    enable = true;
  };
}
