{ config, pkgs, pkgsUnstable, libs, ... }:
{

  home.packages = with pkgs; [
    unstable.rustup
    #unstable.rust-analyzer
    gcc
    openssl
    #libiconv
    pkg-config
    #    cargo
    #    rustc
    #    rust-analyzer-unwrapped
    #    rustfmt
    #    clippy
    libiconv
    pkg-config

    # used for jupiter search
    ffmpeg
    stt
  ];

  home.sessionVariables = {
    PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
  };



}
