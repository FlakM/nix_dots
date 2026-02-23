{ config, pkgs, lib, ... }:
let
  registry = import ./default.nix;
  # Only include devices with valid IDs - add air/work when real IDs are obtained
  allDevices = [ "amd-pc" "pixel" ];
in
{
  sops.defaultSopsFile = ../../secrets/secrets.yaml;

  services.syncthing = {
    enable = true;
    user = "flakm";
    dataDir = "/home/flakm";
    configDir = "/home/flakm/.config/syncthing";
    overrideDevices = true;
    overrideFolders = true;

    settings = {
      devices = builtins.listToAttrs (map
        (name: {
          inherit name;
          value = { id = registry.devices.${name}.id; };
        })
        allDevices);

      folders = {
        "${registry.folders.family-vault.id}" = {
          path = "/var/lib/syncthing/encrypted/family-vault";
          devices = allDevices;
          type = "receiveencrypted";
        };

        "${registry.folders.work-vault.id}" = {
          path = "/var/lib/syncthing/encrypted/work-vault";
          devices = allDevices;
          type = "receiveencrypted";
        };
      };

      options = {
        urAccepted = -1;
        localAnnounceEnabled = true;
        relaysEnabled = true;
      };

      gui.address = "127.0.0.1:8384";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/syncthing 0755 flakm users -"
    "d /var/lib/syncthing/encrypted 0755 flakm users -"
    "d /var/lib/syncthing/encrypted/family-vault 0755 flakm users -"
    "d /var/lib/syncthing/encrypted/work-vault 0755 flakm users -"
  ];

  services.nginx = {
    enable = true;
    virtualHosts."syncthing.house.flakm.com" = {
      forceSSL = true;
      useACMEHost = "house.flakm.com";
      locations."/" = {
        proxyPass = "http://127.0.0.1:8384";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;

          # Security headers
          add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
          add_header X-Content-Type-Options "nosniff" always;
          add_header X-Frame-Options "SAMEORIGIN" always;
        '';
      };
    };
  };
}
