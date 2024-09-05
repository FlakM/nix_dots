{ config, pkgs, pkgs-unstable, ... }:
{

  home.packages = with pkgs; [
    #    rustup
    mold
    clang
    #gcc
    #openssl
    #libiconv
    pkg-config
    #    cargo
    #    rustc
    #    rust-analyzer-unwrapped
    #    rustfmt
    #    clippy
    libiconv

    heaptrack
    gdb
    lldb

    rustfilt


    probe-rs
  ] ++ lib.optionals stdenv.isDarwin [
    libiconv
  ];


  home.file.".cargo/config.toml".text = ''
    [target.x86_64-unknown-linux-gnu]
    linker = "clang"
    rustflags = ["-C", "link-arg=-fuse-ld=${pkgs-unstable.mold-wrapped}/bin/mold"]
  '';

  home.sessionVariables = {
    #  PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig;${pkgs.libiconv}/lib/";
    CARGO_TARGET_DIR = "${config.home.homeDirectory}/.cargo/target";
  };



}
