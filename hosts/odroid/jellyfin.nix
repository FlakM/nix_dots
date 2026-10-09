{ pkgs, pkgs-unstable, config, lib, ... }: {
  nixpkgs.overlays = [
    (self: super: {
      vaapiIntel = super.vaapiIntel.override { enableHybridCodec = true; };
    })
  ];

  hardware.graphics = {
    enable = true;
    extraPackages = lib.mkForce (with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libva-vdpau-driver
      libvdpau-va-gl
      intel-compute-runtime-legacy1
      vpl-gpu-rt
      # QSV not supported on Jasper Lake - use VAAPI in Jellyfin settings
    ]);
  };

  hardware.firmware = with pkgs; [ linux-firmware ];

  services.jellyfin = {
    enable = true;
    group = "jellyfin";
  };

  systemd.services.jellyfin = {
    serviceConfig = {
      SupplementaryGroups = [ "render" "video" "media" ];
      DeviceAllow = [ "/dev/dri/renderD128 rw" ];

      ProtectHome = true;
      # 26.05's jellyfin module now sets ProtectSystem = true; override to strict.
      ProtectSystem = lib.mkForce "strict";
      ReadWritePaths = [ "/var/lib/jellyfin" "/var/cache/jellyfin" ];
      # ZFS mounts need explicit BindPaths for proper write access within the namespace
      BindPaths = [ "/var/media" ];

      PrivateUsers = lib.mkForce false;
      RestrictNamespaces = lib.mkForce false;
    };
  };

  networking.firewall.allowedTCPPorts = [ 443 8096 ];

  services.nginx = {
    enable = true;
    virtualHosts = {
      "jellyfin.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        forceSSL = true;
        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:8096;
            proxy_redirect http://127.0.0.1:8096 https://jellyfin.house.flakm.com;
          '';
        };
      };

      "jellyseerr.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        #serverAliases = [ "*.house.flakm.com" ];                                                                                                                                                                                                                                     
        forceSSL = true;
        locations."/" = {
          extraConfig = ''                                                                                                                                                                                                                                                            
            proxy_set_header Host $host; # try $host instead if this doesn't work                                                                                                                                                                                                     
            proxy_set_header X-Forwarded-Proto $scheme;                                                                                                                                                                                                                               
            proxy_pass http://127.0.0.1:5055;                                                                                                                                                                                                                                         
            proxy_redirect http://127.0.0.1:5055 https://jellyseerr.house.flakm.com;                                                                                                                                                                                                  
          '';
        };
      };

      "sonarr.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        #serverAliases = [ "*.house.flakm.com" ];                                                                                                                                                                                                                                     
        forceSSL = true;
        locations."/" = {
          extraConfig = ''                                                                                                                                                                                                                                                            
            proxy_set_header Host $host; # try $host instead if this doesn't work                                                                                                                                                                                                     
            proxy_set_header X-Forwarded-Proto $scheme;                                                                                                                                                                                                                               
            proxy_pass http://127.0.0.1:8989;                                                                                                                                                                                                                                         
            proxy_redirect http://127.0.0.1:8989 https://sonarr.house.flakm.com;                                                                                                                                                                                                      
          '';
        };
      };


      "sabnzbd.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        #serverAliases = [ "*.house.flakm.com" ];                                                                                                                                                                                                                                     
        forceSSL = true;
        locations."/" = {
          extraConfig = ''                                                                                                                                                                                                                                                            
            proxy_set_header Host $host; # try $host instead if this doesn't work                                                                                                                                                                                                     
            proxy_set_header X-Forwarded-Proto $scheme;                                                                                                                                                                                                                               
            proxy_pass http://127.0.0.1:8080;                                                                                                                                                                                                                                         
            proxy_redirect http://127.0.0.1:8080 https://sabnzbd.house.flakm.com;                                                                                                                                                                                                     
          '';
        };
      };

      "radarr.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        forceSSL = true;
        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:7878;
            proxy_redirect http://127.0.0.1:7878 https://radarr.house.flakm.com;
          '';
        };
      };


      "readarr.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        #serverAliases = [ "*.house.flakm.com" ];                                                                                                                                                                                                                                     
        forceSSL = true;
        locations."/" = {
          extraConfig = ''                                                                                                                                                                                                                                                            
            proxy_set_header Host $host; # try $host instead if this doesn't work                                                                                                                                                                                                     
            proxy_set_header X-Forwarded-Proto $scheme;                                                                                                                                                                                                                               
            proxy_pass http://127.0.0.1:8787;                                                                                                                                                                                                                                         
            proxy_redirect http://127.0.0.1:8787 https://readarr.house.flakm.com;                                                                                                                                                                                                     
          '';
        };
      };
    };
  };

  environment.systemPackages = with pkgs; [
    #ffmpeg
  ];



  services.seerr = {
    enable = true;
  };

  services.sonarr.enable = true;

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.nzb_api_key = {
    sopsFile = ../../secrets/secrets.yaml;
  };

  systemd.services.sonarr-nzbgeek-key = {
    description = "Sync and test Sonarr's NZBgeek API key";
    wantedBy = [ "multi-user.target" ];
    requires = [ "sonarr.service" ];
    after = [ "sonarr.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.python3}/bin/python3 - <<'PY'
      import json
      import time
      import urllib.request
      import xml.etree.ElementTree as ET
      from pathlib import Path

      secret = Path("${config.sops.secrets.nzb_api_key.path}").read_text().strip()
      if not secret:
          raise SystemExit("NZBgeek key is empty")

      api_key = ET.parse("/var/lib/sonarr/.config/NzbDrone/config.xml").findtext("ApiKey")
      base = "http://127.0.0.1:8989/api/v3/"
      headers = {"X-Api-Key": api_key, "Content-Type": "application/json"}

      def request(path, method="GET", data=None):
          body = json.dumps(data).encode() if data is not None else None
          req = urllib.request.Request(base + path, headers=headers, data=body, method=method)
          with urllib.request.urlopen(req, timeout=30) as response:
              return json.load(response) if response.status != 204 else None

      for attempt in range(30):
          try:
              indexers = request("indexer")
              break
          except OSError:
              if attempt == 29:
                  raise
              time.sleep(1)

      matches = [indexer for indexer in indexers if indexer["name"] == "NZBgeek"]
      if len(matches) != 1:
          raise SystemExit("Expected exactly one NZBgeek indexer")
      indexer = matches[0]
      fields = [field for field in indexer["fields"] if field["name"] == "apiKey"]
      if len(fields) != 1:
          raise SystemExit("NZBgeek API key field is missing")

      fields[0]["value"] = secret
      request("indexer/test", "POST", indexer)
      request("indexer/" + str(indexer["id"]), "PUT", indexer)
      print("NZBgeek key applied and tested")
      PY
    '';
  };

  systemd.timers.sonarr-nzbgeek-key = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  services.sabnzbd = {
    enable = true;
    # 26.05 deprecates configFile in favour of settings. With stateVersion < 26.05
    # allowConfigWrite defaults true, so the existing /var/lib/sabnzbd/sabnzbd.ini
    # (servers, api keys, paths) is merged in as the base; we only re-assert the
    # few misc values whose option defaults would otherwise reset the live ones.
    configFile = null;
    settings.misc = {
      bandwidth_max = "1024M";
      bandwidth_perc = 100;
      cache_limit = "1G";
    };
  };

  services.radarr.enable = true;

  services.readarr.enable = true;

}
