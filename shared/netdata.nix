{ pkgs, ... }:
{
  services.netdata = {
    enable = true;
    config = {
      global = {
        # uncomment to reduce memory to 32 MB
        #"page cache size" = 32;

        # update interval
        #"update every" = 5;
      };
      ml = {
        # enable machine learning - set to yes
        "enabled" = "no";
      };
    };
  };



  services.nginx = {
    enable = true;
    virtualHosts = {
      "netdata.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        forceSSL = true;
        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host; # try $host instead if this doesn't work
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:19999; # replace port
            proxy_redirect http://127.0.0.1:19999 https://netdata.house.flakm.com; # replace port
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

