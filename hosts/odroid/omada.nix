{ ... }: {

  # TP-Link Omada controller. No native nixpkgs package/module exists, so we run
  # the community mbentley image under podman. Host networking is used because
  # the controller relies on LAN broadcast/discovery to adopt devices.
  virtualisation.oci-containers.containers.omada-controller = {
    image = "mbentley/omada-controller:5.15";
    extraOptions = [
      "--network=host"
      # Omada takes a while to warm up; the image healthcheck leaves transient
      # failed systemd units during normal boot.
      "--no-healthcheck"
    ];
    volumes = [
      "omada-data:/opt/tplink/EAPController/data"
      "omada-logs:/opt/tplink/EAPController/logs"
    ];
    environment = {
      TZ = "Europe/Warsaw";
      MANAGE_HTTP_PORT = "8088";
      MANAGE_HTTPS_PORT = "8043";
      PORTAL_HTTP_PORT = "8088";
      PORTAL_HTTPS_PORT = "8843";
      SHOW_SERVER_LOGS = "true";
      SHOW_MONGODB_LOGS = "false";
    };
  };

  services.nginx = {
    enable = true;
    virtualHosts."omada.house.flakm.com" = {
      useACMEHost = "house.flakm.com";
      forceSSL = true;
      locations."/" = {
        # Omada management runs over HTTPS with a self-signed cert.
        proxyPass = "https://127.0.0.1:8043";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_ssl_verify off;
          client_max_body_size 0;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;

          # Omada ships large uncompressed JS/CSS bundles (g6 alone is ~1MB)
          # and gzips nothing itself, so compress at the proxy.
          gzip on;
          gzip_proxied any;
          gzip_comp_level 5;
          gzip_min_length 1024;
          gzip_vary on;
          gzip_types text/plain text/css application/json application/javascript text/javascript application/x-javascript image/svg+xml;
        '';
      };
    };
  };

  # Host-networked container binds these directly on the host.
  networking.firewall = {
    allowedTCPPorts = [
      8088 # management / portal HTTP
      8043 # management HTTPS
      8843 # portal HTTPS
      29811 # device adoption
      29812 # device management
      29813 # device upgrade
      29814 # manager v2
      29815 # transfer v2
      29816 # RTTY (remote terminal)
    ];
    allowedUDPPorts = [
      27001 # controller discovery
      29810 # device discovery
    ];
  };

}
