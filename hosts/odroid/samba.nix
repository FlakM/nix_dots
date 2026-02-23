{ pkgs, config, inputs, ... }: {

  # SOPS secret for Samba password
  sops.defaultSopsFile = ../../secrets/secrets.yaml;
  sops.secrets.samba_flakm_password = {
    mode = "0440";
    owner = "root";
    group = "root";
    restartUnits = [ "samba-setup-flakm.service" ];
  };

  networking.firewall.enable = true;
  networking.firewall.allowPing = true;
  services.samba.openFirewall = true;

  services.samba-wsdd.enable = true; # make shares visible for windows 10 clients
  networking.firewall.allowedTCPPorts = [
    5357 # wsdd
  ];
  networking.firewall.allowedUDPPorts = [
    3702 # wsdd
  ];
  services.samba = {
    enable = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "smbnix";
        "netbios name" = "smbnix";
        security = "user";
        #use sendfile = yes
        #max protocol = smb2
        # note: localhost is the ipv6 localhost ::1
        "hosts allow" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
      smolnica = {
        path = "/var/data/smolnica";
        browseable = "no";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "smolnica";
        "force group" = "smolnica";
      };

      victor = {
        path = "/var/data/victor";
        browseable = "no";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "victor";
        "force group" = "victor";
      };

      kleszczow = {
        path = "/var/data/kleszczow";
        browseable = "no";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "kleszczow";
        "force group" = "kleszczow";
      };

      paperless-consume = {
        path = "/var/lib/paperless/consume";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "flakm";
        "create mask" = "0664";
        "directory mask" = "0775";
        "force user" = "paperless";
        "force group" = "paperless";
        comment = "Paperless document consumption directory";
      };
    };
  };

  # Systemd service to automatically set Samba password for flakm user
  systemd.services.samba-setup-flakm = {
    description = "Set up Samba password for flakm user";
    wantedBy = [ "multi-user.target" ];
    after = [ "samba-smbd.service" "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
      ExecStart = pkgs.writeShellScript "setup-samba-flakm" ''
        set -e
        # Wait for samba services to be ready
        sleep 2
        
        # Set Samba password for flakm user using SOPS secret
        if [ -f "${config.sops.secrets.samba_flakm_password.path}" ]; then
          password=$(cat "${config.sops.secrets.samba_flakm_password.path}")
          echo -e "$password\n$password" | ${pkgs.samba}/bin/smbpasswd -a -s flakm
          echo "Samba password set for flakm user from SOPS secret"
        else
          echo "SOPS secret file not found: ${config.sops.secrets.samba_flakm_password.path}"
          exit 1
        fi
      '';
    };
  };
}
