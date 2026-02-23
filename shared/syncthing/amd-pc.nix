{ config, pkgs, lib, ... }:
let
  registry = import ./default.nix;
  # Only include devices with valid IDs - add air/work when real IDs are obtained
  trustedDevices = [ "pixel" ];
in
{
  sops.defaultSopsFile = ../../secrets/secrets.yaml;

  sops.secrets = {
    syncthing_family_vault_password = {
      restartUnits = [ "syncthing.service" ];
      mode = "0400";
      owner = config.users.users.flakm.name;
    };
    syncthing_work_vault_password = {
      restartUnits = [ "syncthing.service" ];
      mode = "0400";
      owner = config.users.users.flakm.name;
    };
  };

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
        (trustedDevices ++ [ "odroid" ]));

      folders = {
        "${registry.folders.family-vault.id}" = {
          path = "/home/flakm/obsidian/family";
          devices = trustedDevices ++ [
            { name = "odroid"; encryptionPasswordFile = config.sops.secrets.syncthing_family_vault_password.path; }
          ];
          type = "sendreceive";
          versioning = {
            type = "staggered";
            params = {
              cleanInterval = "3600";
              maxAge = "31536000";
            };
          };
        };

        "${registry.folders.work-vault.id}" = {
          path = "/home/flakm/obsidian/work";
          devices = trustedDevices ++ [
            { name = "odroid"; encryptionPasswordFile = config.sops.secrets.syncthing_work_vault_password.path; }
          ];
          type = "sendreceive";
          versioning = {
            type = "staggered";
            params = {
              cleanInterval = "3600";
              maxAge = "31536000";
            };
          };
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

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "syncthing-info" ''
      echo "=== Syncthing Device Information ==="
      echo ""
      echo "This device (amd-pc):"
      MYID=$(syncthing cli show system 2>/dev/null | ${pkgs.jq}/bin/jq -r '.myID' || echo "unknown")
      echo "  ID: $MYID"
      echo ""
      echo "Configured devices:"
      echo "  odroid: ${registry.devices.odroid.id}"
      echo "  pixel:  ${registry.devices.pixel.id}"
      echo "  air:    (not configured - add ID to default.nix)"
      echo "  work:   (not configured - add ID to default.nix)"
      echo ""
      echo "=== Folder IDs ==="
      echo "  family-vault: ${registry.folders.family-vault.id}"
      echo "  work-vault:   ${registry.folders.work-vault.id}"
      echo ""
      echo "=== Vault Paths ==="
      echo "  family: ~/obsidian/family"
      echo "  work:   ~/obsidian/work"
      echo ""
      echo "=== Connection Status ==="
      syncthing cli show connections 2>/dev/null | ${pkgs.jq}/bin/jq -r '.connections | to_entries[] | "\(.key[:7]): connected=\(.value.connected)"' || echo "Unable to query"
      echo ""
      echo "=== New Device Setup ==="
      echo "1. Install Syncthing on new device"
      echo "2. Get device ID: syncthing cli show system | jq -r '.myID'"
      echo "3. Add device ID to shared/syncthing/default.nix"
      echo "4. Add device name to amd-pc.nix and odroid.nix"
      echo "5. Rebuild NixOS on amd-pc and odroid"
      echo "6. Accept folder shares on new device"
    '')
  ];
}
