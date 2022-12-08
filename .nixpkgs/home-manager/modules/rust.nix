{ config, pkgs, pkgsUnstable, libs, ... }:
{

  home.packages = with pkgs; [
    rustup
    rust-analyzer
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
  ] ++ lib.optionals stdenv.isDarwin [
     libiconv
  ];

  #home.sessionVariables = {
  #  PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig;${pkgs.libiconv}/lib/";
  #};



}
