{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "kitchenowl.house.flakm.com";
  dataDir = "/var/lib/kitchenowl";
  uid = 988;
  gid = 988;
  # uwsgi in the all-in-one image listens on 8080 (nginx static + /api proxy).
  port = 8210;
in
{
  # KitchenOwl (grocery list + recipe manager) has no nixpkgs package or
  # NixOS module, so run the upstream all-in-one image under podman. It is a
  # single container (Flutter web served by nginx, Flask backend behind
  # uwsgi) with SQLite in /data, which is plenty for one household.
  users.users.kitchenowl = {
    isSystemUser = true;
    uid = uid;
    group = "kitchenowl";
    home = dataDir;
  };

  users.groups.kitchenowl.gid = gid;

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0700 kitchenowl kitchenowl - -"
  ];

  virtualisation.oci-containers.containers.kitchenowl = {
    image = "docker.io/tombursch/kitchenowl:v0.7.10";
    # Loopback only: nginx terminates TLS and serves the public vhost.
    ports = [ "127.0.0.1:${toString port}:8080" ];
    volumes = [
      "${dataDir}:/data"
    ];
    environment = {
      TZ = "Europe/Warsaw";
      STORAGE_PATH = "/data";
      # Read from the persisted data volume instead of an env var so the
      # secret survives container recreation.
      JWT_SECRET_KEY_FILE = "/data/jwt_secret";
      FRONT_URL = "https://${domain}";
    };
  };

  # The container needs a stable JWT secret, otherwise every restart logs
  # everybody out. Generate one on first start; the file lives on the data
  # volume and is never committed anywhere.
  systemd.services.podman-kitchenowl = {
    preStart = lib.mkBefore ''
      umask 077
      if [ ! -s ${dataDir}/jwt_secret ]; then
        ${pkgs.openssl}/bin/openssl rand -hex 32 > ${dataDir}/jwt_secret
      fi
    '';
    serviceConfig.RestartSec = "10s";
  };

  services.nginx.virtualHosts."${domain}" = {
    useACMEHost = "house.flakm.com";
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = ''
        # Recipe photos are uploaded through the same origin.
        client_max_body_size 25m;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
      '';
    };
  };
}
