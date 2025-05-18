{ pkgs, lib, config, inputs, pkgs-unstable, ... }: {

  services.uptime-kuma = {
    enable = true;
  };



  services.nginx = {
    enable = true;
    virtualHosts = {
      "uptime-kuma.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        forceSSL = true;
        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host; # try $host instead if this doesn't work
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:3001; # replace port
            proxy_redirect http://127.0.0.1:3001 https://uptime-kuma.house.flakm.com;'';
        };
      };
    };
  };


}
