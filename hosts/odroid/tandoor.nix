{ pkgs, config, inputs, ... }: {

  services.tandoor-recipes = {
    package = pkgs.unstable.tandoor-recipes;
    enable = true;
    port = 3030;
    address = "127.0.0.1";
    extraConfig = {
      DB_ENGINE= "django.db.backends.postgresql";
      POSTGRES_HOST="/run/postgresql";
      POSTGRES_USER="tandoor";
      POSTGRES_DB="tandoor";
    };
  };

  networking.firewall.allowedTCPPorts = [ 443 3030 ];

  services.nginx = {
    enable = true;
    virtualHosts = {
      "tandoor.house.flakm.com" = {
        enableACME = false; # Since you're providing your own certs
        forceSSL = true;

        sslCertificate = "/var/secrets/certs/house.crt";
        sslCertificateKey = "/var/secrets/certs/house.key";

        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host; # try $host instead if this doesn't work
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:3030; # replace port
            proxy_redirect http://127.0.0.1:3030 https://recipes.domain.tld; # replace port and domain
          '';
        };
      };
    };
  };


}
