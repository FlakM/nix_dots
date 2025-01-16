{ inputs, config, pkgs, pkgs-unstable, pkgs-master, ... }:
let
  fenix = inputs.fenix.packages.${pkgs.system};
in
{

  home.packages = with pkgs; [
    #    rustup
    mold
    clang
    #gcc
    #openssl
    #libiconv
    pkg-config
    zlib
    #    cargo
    #    rustc
    #    rust-analyzer-unwrapped
    #    rustfmt
    #    clippy

    rustfilt

    fenix.latest.rust-analyzer



    openssl
    rdkafka
    cmake

    probe-rs

    gnumake
    rust-jemalloc-sys
    protobuf
  ] ++ lib.optionals stdenv.isDarwin [
    libiconv
  ] ++ lib.optionals stdenv.isLinux [
    gdb
    heaptrack
  ];


  home.file.".cargo/config.toml".text = ''
    [target.x86_64-unknown-linux-gnu]
    linker = "clang"
    rustflags = ["-C", "link-arg=-fuse-ld=${pkgs-unstable.mold-wrapped}/bin/mold", "--cfg", "tokio_unstable"]
    #rustdocflags = ["--cfg", "tokio_unstable"] 
  '';

  home.sessionVariables = {
    #  PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig;${pkgs.libiconv}/lib/";
    CARGO_TARGET_DIR = "${config.home.homeDirectory}/.cargo/target";
  };



}
