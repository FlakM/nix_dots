{ config, pkgs, lib, ... }:
let
  certDir = config.security.acme.certs."house.flakm.com".directory;
in
{
  networking.firewall.allowedTCPPorts = [ 1883 8883 ];

  users.users.mosquitto.extraGroups = [ "acme" ];

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        # Plain MQTT for LAN devices (ESP32, etc.)
        port = 1883;
        address = "0.0.0.0";
        settings.allow_anonymous = true;
        acl = [ "topic readwrite #" ];
      }
      {
        # MQTTS with TLS for external/secure access
        port = 8883;
        address = "0.0.0.0";
        settings = {
          allow_anonymous = true;
          certfile = "${certDir}/cert.pem";
          keyfile = "${certDir}/key.pem";
          cafile = "${certDir}/chain.pem";
        };
        acl = [ "topic readwrite #" ];
      }
    ];
  };

  # Reload mosquitto when ACME cert renews
  security.acme.certs."house.flakm.com".reloadServices = [ "mosquitto" ];
}
