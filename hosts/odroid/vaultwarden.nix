{ config, ... }:
let
  domain = "vault.house.flakm.com";
  port = 8222;
in
{
  services.vaultwarden = {
    enable = true;
    backupDir = "/var/local/vaultwarden/backup";
    config = {
      DOMAIN = "https://${domain}";
      SIGNUPS_ALLOWED = false;
      INVITATIONS_ALLOWED = false;
      SHOW_PASSWORD_HINT = false;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = port;
      ROCKET_LOG = "critical";
      LOGIN_RATELIMIT_SECONDS = 60;
      LOGIN_RATELIMIT_MAX_BURST = 10;
      ADMIN_RATELIMIT_SECONDS = 300;
      ADMIN_RATELIMIT_MAX_BURST = 3;
      IP_HEADER = "X-Real-IP";
    };
    environmentFile = config.sops.secrets.vaultwarden_env.path;
  };

  sops.defaultSopsFile = ../../secrets/secrets.yaml;
  sops.secrets.vaultwarden_env = {
    restartUnits = [ "vaultwarden.service" ];
    mode = "0400";
  };

  services.nginx.virtualHosts."${domain}" = {
    useACMEHost = "house.flakm.com";
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };
}
