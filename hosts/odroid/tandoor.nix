{ pkgs, lib, config, inputs, pkgs-unstable, ... }: {

  services.tandoor-recipes = {
    package = pkgs-unstable.tandoor-recipes;
    enable = true;
    port = 3030;
    address = "127.0.0.1";
    extraConfig = {
      DB_ENGINE = "django.db.backends.postgresql";
      POSTGRES_HOST = "/run/postgresql";
      # to enter psql run: `psql -h /run/postgresql -U postgres`
      # ALTER USER tandoor WITH SUPERUSER;
      # was required to get migrations to work
      # and than ALTER USER tandoor WITH NOSUPERUSER ; to roll back
      POSTGRES_USER = "tandoor";
      POSTGRES_DB = "tandoor";
      #MEDIA_URL = "https://tandoor.house.flakm.com/";
      GUNICORN_MEDIA = "0";
    };
  };

  networking.firewall.allowedTCPPorts = [ 443 3030 ];

  users.groups.tandoor-recipes.members = [ "nginx" ];

  services.nginx.user = "nginx";

  services.nginx = {
    enable = true;
    virtualHosts = {
      "tandoor.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        forceSSL = true;
        locations = {
          "/media/".alias = "/var/lib/tandoor-recipes/";
          "/" = {
            proxyPass = "http://127.0.0.1:3030";
            recommendedProxySettings = true;
            #extraConfig = ''
            #  proxy_set_header Host $http_host; # try $host instead if this doesn't work
            #  proxy_set_header X-Forwarded-Proto $scheme;
            #  proxy_pass http://127.0.0.1:3030; # replace port
            #  proxy_redirect http://127.0.0.1:3030 https://recipes.domain.tld; # replace port and domain
            #'';
          };
        };
      };
    };
  };


}
