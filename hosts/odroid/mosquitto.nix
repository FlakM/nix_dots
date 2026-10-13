{ config, pkgs, lib, ... }:
let
  certDir = config.security.acme.certs."house.flakm.com".directory;
  mqttAcl = [
    "readwrite frigate/#"
    "readwrite home/#"
    "readwrite lionelo/#"
    "readwrite eas/#"
    "readwrite ebusd/#"
  ];
in
{
  # 1883 stays loopback-only (trusted local clients: HA, Frigate, ebusd,
  # scripts). 1884 is the authenticated listener for LAN/tailnet clients.
  networking.firewall.allowedTCPPorts = [ 1884 8883 ];

  users.users.mosquitto.extraGroups = [ "acme" ];

  # Shared MQTT credential; the mosquitto module hashes it into a per-listener
  # password file via systemd credentials.
  sops.secrets.mqtt_password = { };

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        # Trusted local clients over loopback (no auth).
        port = 1883;
        address = "127.0.0.1";
        omitPasswordAuth = true;
        settings.allow_anonymous = true;
      }
      {
        # Authenticated MQTT for LAN/tailnet clients (quickshell, ESP board).
        port = 1884;
        address = "0.0.0.0";
        users.mqtt = {
          passwordFile = config.sops.secrets.mqtt_password.path;
          acl = mqttAcl;
        };
      }
      {
        # Authenticated MQTTS for external clients.
        port = 8883;
        address = "0.0.0.0";
        settings = {
          certfile = "${certDir}/cert.pem";
          keyfile = "${certDir}/key.pem";
          cafile = "${certDir}/chain.pem";
        };
        users.mqtt = {
          passwordFile = config.sops.secrets.mqtt_password.path;
          acl = mqttAcl;
        };
      }
    ];
  };

  # Reload mosquitto when ACME cert renews
  security.acme.certs."house.flakm.com".reloadServices = [ "mosquitto" ];
}
