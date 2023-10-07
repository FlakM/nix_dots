{ config, pkgs, pkgsUnstable, libs, ... }:
{
  home.packages = with pkgs; [
    rustup
    mold
    clang
    #gcc
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

    heaptrack
    gdb
    lldb
    openssl
  ] ++ lib.optionals stdenv.isDarwin [
    libiconv
  ];


  # home.file.".cargo/config.toml".text = ''
  #   [target.x86_64-unknown-linux-gnu]
  #   linker = "clang"
  #   rustflags = ["-C", "link-arg=-fuse-ld=${pkgs.mold}/bin/mold"]
  # '';

  #home.sessionVariables = {
  #  PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig;${pkgs.libiconv}/lib/";
  #};


  home.file.".cargo/config.toml".text = ''
    #[target.x86_64-unknown-linux-gnu]
    #linker = "clang"
    #rustflags = ["-C", "link-arg=-fuse-ld=${pkgs.mold}/bin/mold"]

    [registries.crates-io]
    protocol = "sparse"
  '';

}