{ pkgs, ... }:
let
  port = 5580;
  stateDir = "/var/lib/matter-server";
in
{
  # The Matter SDK writes its factory config to /data.
  systemd.tmpfiles.rules = [
    "d /data 0750 hass hass -"
  ];

  systemd.services.matter-server = {
    description = "Matter Server for Home Assistant";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "simple";
      User = "hass";
      Group = "hass";
      ExecStart = "${pkgs.python-matter-server}/bin/matter-server --storage-path ${stateDir} --paa-root-cert-dir ${stateDir}/paa-root-certs --port ${toString port} --listen-address 127.0.0.1 --primary-interface enp2s0 --log-level info";
      Restart = "on-failure";
      RestartSec = 5;
      StateDirectory = "matter-server";
      StateDirectoryMode = "0750";
    };
  };
}
