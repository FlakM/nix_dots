{ config, lib, pkgs, inputs, ... }:
let
  inherit (pkgs) stdenv;
  einkPkgs = inputs.eink-bridge.packages.${pkgs.stdenv.hostPlatform.system};
  eink-bridge = einkPkgs.default;
  hasHarness = einkPkgs ? harness;
  harness = if hasHarness then einkPkgs.harness else null;
  hasChannel = einkPkgs ? einkChannel;
  einkChannel = if hasChannel then einkPkgs.einkChannel else null;
  servicePath = lib.concatStringsSep ":" (
    (config.home.sessionPath or [ ])
    ++ [
      "/etc/profiles/per-user/${config.home.username}/bin"
      "/run/wrappers/bin"
      "/nix/var/nix/profiles/default/bin"
      "/run/current-system/sw/bin"
    ]
  );

  # Build home.file entries for each skill directory in the harness
  skillFiles = if hasHarness then
    builtins.listToAttrs (map (name: {
      name = ".claude/skills/${name}";
      value = { force = true; source = "${harness}/skills/${name}"; };
    }) (builtins.attrNames (builtins.readDir "${harness}/skills")))
  else { };

  styleFiles = if hasHarness then
    builtins.listToAttrs (map (name: {
      name = ".claude/output-styles/${name}";
      value = { force = true; source = "${harness}/output-styles/${name}"; };
    }) (builtins.attrNames (builtins.readDir "${harness}/output-styles")))
  else { };
in
{
  home.packages = [
    eink-bridge
  ] ++ lib.optional hasChannel einkChannel;

  home.file = skillFiles // styleFiles;

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
