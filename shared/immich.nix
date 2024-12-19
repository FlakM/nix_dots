{ pkgs, config, ... }:

{

  services.immich = {
    enable = true;
  };


  services.nginx = {
    enable = true;
    virtualHosts = {
      "immich.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        forceSSL = true;
        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host; # try $host instead if this doesn't work
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:${toString config.services.immich.port};
            proxy_redirect http://127.0.0.1:${toString config.services.immich.port} https://immich.house.flakm.com; # replace port
            proxy_http_version 1.1;
            proxy_pass_request_headers on;
            proxy_set_header Connection "keep-alive";
            proxy_store off;
          '';
        };
      };
    };
  };

}
