{ config, lib, pkgs, inputs, ... }:
let
  inherit (pkgs) stdenv;
  eink-bridge = inputs.eink-bridge.packages.${pkgs.system}.default;
  servicePath = lib.concatStringsSep ":" (
    (config.home.sessionPath or [ ])
    ++ [
      "/etc/profiles/per-user/${config.home.username}/bin"
      "/run/wrappers/bin"
      "/nix/var/nix/profiles/default/bin"
      "/run/current-system/sw/bin"
    ]
  );
in
{
  home.packages = [
    eink-bridge
  ];

  systemd.user.services."eink-serve" = lib.mkIf stdenv.isLinux {
    Unit = {
      Description = "eink-bridge review server";
      After = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "${eink-bridge}/bin/eink-serve";
      Restart = "on-failure";
      RestartSec = 5;
      Environment = [
        "RUST_LOG=info"
        "PATH=${servicePath}"
      ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
