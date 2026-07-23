{ config, pkgs, pkgs-master, ... }:
let
  domain = "tasks.house.flakm.com";
  port = 3456;
in
{
  services.vikunja = {
    enable = true;
    package = pkgs-master.vikunja;
    address = "127.0.0.1";
    inherit port;
    frontendScheme = "https";
    frontendHostname = domain;
    database = {
      type = "postgres";
      host = "/run/postgresql";
      user = "vikunja";
      database = "vikunja";
    };
    settings = {
      service = {
        enableregistration = false;
        enablelinksharing = false;
        timezone = config.time.timeZone;
        ipextractionmethod = "xff";
        trustedproxies = "127.0.0.1/32";
        secret.file = "/var/lib/vikunja/secret";
      };
      files.maxsize = "50MB";
      ratelimit.enabled = true;
    };
  };

  services.postgresql = {
    ensureDatabases = [ "vikunja" ];
    ensureUsers = [
      {
        name = "vikunja";
        ensureDBOwnership = true;
      }
    ];
  };

  systemd.services.vikunja = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
    preStart = ''
      if [[ ! -s /var/lib/vikunja/secret ]]; then
        umask 077
        ${pkgs.openssl}/bin/openssl rand -hex 32 > /var/lib/vikunja/secret
      fi
    '';
  };

  services.nginx.virtualHosts."${domain}" = {
    useACMEHost = "house.flakm.com";
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = ''
        client_max_body_size 50M;
      '';
    };
  };
}
