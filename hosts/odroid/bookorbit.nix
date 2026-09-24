{ pkgs, ... }:
let
  domain = "bookorbit.house.flakm.com";
  dataDir = "/var/lib/bookorbit";
  secretsDir = "${dataDir}/secrets";
in
{
  users.users.bookorbit = {
    isSystemUser = true;
    uid = 982;
    group = "media";
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root - -"
    "d ${dataDir}/app 0770 bookorbit media - -"
    "d ${dataDir}/postgres 0755 root root - -"
    "d /var/media/books 2775 bookorbit media - -"
    "d /var/media/books/ebooks 2775 bookorbit media - -"
    "d /var/media/bookorbit-dock 2775 bookorbit media - -"
  ];

  systemd.services.bookorbit-secrets = {
    description = "Create persistent BookOrbit credentials";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      umask 077
      mkdir -p ${secretsDir}
      chmod 0700 ${secretsDir}
      for name in postgres_password jwt_secret setup_bootstrap_token book_request_encryption_key podcast_encryption_key; do
        if [ ! -s "${secretsDir}/$name" ]; then
          ${pkgs.openssl}/bin/openssl rand -hex 32 > "${secretsDir}/$name"
        fi
      done
      printf 'POSTGRES_PASSWORD=%s\n' "$(< ${secretsDir}/postgres_password)" > ${secretsDir}/postgres.env
    '';
  };

  virtualisation.oci-containers.containers = {
    bookorbit-db = {
      image = "pgvector/pgvector:pg18";
      ports = [ "127.0.0.1:5433:5432" ];
      volumes = [ "${dataDir}/postgres:/var/lib/postgresql/data" ];
      environment = {
        POSTGRES_USER = "bookorbit";
        POSTGRES_DB = "bookorbit";
        PGDATA = "/var/lib/postgresql/data/pgdata";
      };
      environmentFiles = [ "${secretsDir}/postgres.env" ];
    };

    bookorbit-app = {
      image = "ghcr.io/bookorbit/bookorbit:3.0.0";
      dependsOn = [ "bookorbit-db" ];
      extraOptions = [ "--network=host" ];
      volumes = [
        "${dataDir}/app:/data"
        "${secretsDir}:/run/secrets:ro"
        "/var/media:/var/media"
      ];
      environment = {
        NODE_ENV = "production";
        HOST = "127.0.0.1";
        PORT = "3012";
        APP_URL = "https://${domain}";
        POSTGRES_HOST = "127.0.0.1";
        POSTGRES_PORT = "5433";
        POSTGRES_USER = "bookorbit";
        POSTGRES_DB = "bookorbit";
        POSTGRES_PASSWORD = "";
        POSTGRES_PASSWORD_FILE = "/run/secrets/postgres_password";
        JWT_SECRET = "";
        JWT_SECRET_FILE = "/run/secrets/jwt_secret";
        SETUP_BOOTSTRAP_TOKEN = "";
        SETUP_BOOTSTRAP_TOKEN_FILE = "/run/secrets/setup_bootstrap_token";
        BOOK_REQUEST_ENCRYPTION_KEY_FILE = "/run/secrets/book_request_encryption_key";
        PODCAST_ENCRYPTION_KEY_FILE = "/run/secrets/podcast_encryption_key";
        PUID = "982";
        PGID = "972";
        LIBRARY_BROWSE_ROOT = "/var/media";
        BOOK_DOCK_PATH = "/var/media/bookorbit-dock";
        TZ = "Europe/Warsaw";
      };
    };
  };

  systemd.services.podman-bookorbit-db = {
    requires = [ "bookorbit-secrets.service" "systemd-tmpfiles-setup.service" ];
    after = [ "bookorbit-secrets.service" "systemd-tmpfiles-setup.service" ];
  };
  systemd.services.podman-bookorbit-app = {
    requires = [ "bookorbit-secrets.service" "var-media.mount" ];
    after = [ "bookorbit-secrets.service" "var-media.mount" ];
    preStart = ''
      for attempt in $(seq 1 60); do
        if ${pkgs.postgresql_14}/bin/pg_isready -q -h 127.0.0.1 -p 5433 -U bookorbit -d bookorbit; then
          exit 0
        fi
        sleep 2
      done
      exit 1
    '';
    serviceConfig.RestartSec = "5s";
  };

  services.prowlarr.enable = true;

  services.nginx.virtualHosts = {
    "${domain}" = {
      useACMEHost = "house.flakm.com";
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:3012";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          client_max_body_size 2G;
        '';
      };
    };
    "prowlarr.house.flakm.com" = {
      useACMEHost = "house.flakm.com";
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:9696";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
    };
  };
}
