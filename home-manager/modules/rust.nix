{ inputs, config, lib, pkgs, pkgs-unstable, pkgs-master, ... }:
let
  fenix = inputs.fenix.packages.${pkgs.stdenv.hostPlatform.system};
  cargoBuildDir = "${config.home.homeDirectory}/.cache/cargo-build";
in
{
  home.activation.createCargoBuildDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${cargoBuildDir}"
  '';

  home.packages = with pkgs; [
    pkg-config
    zlib
    openssl
    libiconv

    fenix.latest.rust-analyzer
    (fenix.latest.withComponents [
      "cargo"
      "rustc"
      "rust-src"
      "rustfmt"
      "clippy"
    ])

    rdkafka
    cmake
    probe-rs-tools
    gnumake
    rust-jemalloc-sys
    protobuf
    pre-commit
    vscode
    oniguruma
  ] ++ lib.optionals stdenv.isDarwin [
    libiconv
  ] ++ lib.optionals stdenv.isLinux [
    gdb
    heaptrack
  ];


  home.file.".cargo/config.toml".text = ''
    [build]
    # Store build artifacts outside of project directories
    # This keeps target/ small (~25MB) with only final artifacts
    # while build-dir (~600MB+) holds intermediate compilation cache
    # Benefits: smaller ZFS snapshots, no rust-analyzer/cargo conflicts
    build-dir = "${cargoBuildDir}/{workspace-path-hash}"

    [target.x86_64-unknown-linux-gnu]
    linker = "${pkgs.llvmPackages.clang}/bin/clang"
    rustflags = [
      "-C", "link-arg=-fuse-ld=${pkgs.mold}/bin/mold",
      "-C", "link-arg=-L${pkgs.openssl.out}/lib",
      "-C", "link-arg=-Wl,-rpath,${pkgs.openssl.out}/lib",
      "-C", "link-arg=-L${pkgs.zlib}/lib",
      "-C", "link-arg=-Wl,-rpath,${pkgs.zlib}/lib",
      "-C", "link-arg=-L${pkgs.libxml2}/lib",
      "-C", "link-arg=-Wl,-rpath,${pkgs.libxml2}/lib",
      "-C", "link-arg=-L${pkgs.libxslt}/lib",
      "-C", "link-arg=-Wl,-rpath,${pkgs.libxslt}/lib",
      "-C", "link-arg=-L${pkgs.xmlsec}/lib",
      "-C", "link-arg=-Wl,-rpath,${pkgs.xmlsec}/lib",
      "-C", "link-arg=-L${pkgs.libtool.lib}/lib",
      "-C", "link-arg=-Wl,-rpath,${pkgs.libtool.lib}/lib"
    ]

    [target.aarch64-apple-darwin]
    rustflags = ["-L", "${pkgs.libiconv}/lib"]
  '';

  home.sessionVariables = {
    OPENSSL_DIR = "${pkgs.openssl.dev}";
    OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
    OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";
    PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.libiconv}/lib/pkgconfig:${pkgs.zlib.dev}/lib/pkgconfig";
    ZLIB_DIR = "${pkgs.zlib.dev}";
    ZLIB_LIB_DIR = "${pkgs.zlib}/lib";
    ZLIB_INCLUDE_DIR = "${pkgs.zlib.dev}/include";
  };



}
