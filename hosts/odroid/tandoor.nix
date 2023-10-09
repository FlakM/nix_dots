{ pkgs, config, inputs, ... }: {

  services.tandoor-recipes = {
    package = pkgs.unstable.tandoor-recipes;
    enable = true;
    port = 3030;
    extraConfig = {
      #STATIC_URL = "/gotowanie/static/";
      #MEDIA_URL = "https://odroid.tailecbd4.ts.net/gotowanie/media/";
      #BASE_PATH = "https://odroid.tailecbd4.ts.net/gotowanie/";
      #SCRIPT_NAME = "/gotowanie";
      #STATIC_URL = "/gotowanie/static/";
      #MEDIA_URL = "/gotowanie/static/";
    };
    address = "127.0.0.1";

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
