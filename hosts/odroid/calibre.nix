{ pkgs, ... }: {

  networking.firewall.allowedTCPPorts = [ 80 443 8080 8083 ];

  services.calibre-server = {
    enable = true;
    port = 7777;
    host = "127.0.0.1";
  };

  services.calibre-web = {
    enable = true;
  };


  services.nginx = {
    enable = true;
    virtualHosts = {
      "calibre-web.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        forceSSL = true;
        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host; # try $host instead if this doesn't work
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://[::1]:8083; # replace port
            proxy_redirect http://[::1]:8083 https://calibre-web.house.flakm.com;'';
        };
      };


      "calibre.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        forceSSL = true;
        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host; # try $host instead if this doesn't work
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:7777; # replace port
            proxy_redirect http://127.0.0.1:7777 https://calibre.house.flakm.com;'';
        };
      };

    };
  };
}
