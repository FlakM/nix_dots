{ pkgs, lib, config, inputs, pkgs-unstable, pkgs-master, ... }:
let
  port = 9999;
  domain = "mealie.house.flakm.com";

in
{

  services.mealie = {
    enable = true;
    #    package = pkgs-unstable.mealie;
    port = port;
    settings = {
      BASE_URL = domain;
    };
    credentialsFile = config.sops.secrets.open_api_key.path;
    database.createLocally = true;
  };

  systemd.services.mealie.serviceConfig = {
    TimeoutStartSec = "10min";
    Restart = "on-failure";
    RestartSec = "10s";
  };

  sops.defaultSopsFile = ../../secrets/secrets.yaml;
  sops.secrets = {
    open_api_key = {
      restartUnits = [ "mealie.service" ];
      mode = "0440";
      owner = "mealie";
    };
  };


  users.users.mealie = {
    isSystemUser = true;
    group = "mealie";
  };

  users.groups.mealie = { };


  services.nginx = {
    enable = true;
    virtualHosts = {
      "${domain}" = {
        useACMEHost = "house.flakm.com";
        forceSSL = true;
        locations = {
          "/" = {
            proxyPass = "http://127.0.0.1:${toString port}";
            recommendedProxySettings = true;
          };
        };
      };
    };
  };

}
