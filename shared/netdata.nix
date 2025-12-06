{ pkgs, ... }:
{
  services.netdata = {
    enable = true;
    package = pkgs.netdata.override {
      withCloudUi = true;
    };
    enableAnalyticsReporting = false;
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
      web = {
        "default port" = "19999";
        "bind to" = "127.0.0.1";
        "mode" = "static-threaded";
      };
      registry = {
        "enabled" = "no";
      };
      cloud = {
        "enabled" = "no";
      };
      "global statistics" = {
        "enabled" = "no";
      };
    };
    claimTokenFile = null;
  };



  services.nginx = {
    enable = true;
    virtualHosts = {
      "netdata.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        forceSSL = true;
        locations."= /" = {
          return = "301 https://netdata.house.flakm.com/v3";
        };
        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass http://127.0.0.1:19999;
            proxy_redirect http://127.0.0.1:19999 https://netdata.house.flakm.com;
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

