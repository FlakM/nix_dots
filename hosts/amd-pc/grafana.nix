{ config, pkgs, lib, inputs, modulesPath, ... }: {

  services.grafana = {
    enable = true;
    settings = {
      server = {
        # Listening Address
        http_addr = "127.0.0.1";
        # and Port
        http_port = 3000;
        # Grafana needs to know on which domain and URL it's running
        domain = "grafana.local";
        #root_url = "http:///localhost:3000/"; # Not needed if it is `https://your.domain/`
        serve_from_sub_path = true;
      };
    };
  };

  services.tempo = {
    enable = true;
    settings = {
      server = {
        http_listen_address = "127.0.0.1";
        http_listen_port = 3200;
        grpc_listen_port = 3201;
      };
      storage = {
        trace = {
          backend = "local";
          local.path = "/var/lib/tempo";
          wal.path = "/var/lib/tempo";
        };
      };

      distributor = {
        receivers = {
          otlp = {
            protocols = {
              http = { };
            };
          };
        };
      };
    };
  };


  services.nginx.virtualHosts.${config.services.grafana.domain} = {
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.grafana.port}";
      proxyWebsockets = true;
    };
  };


  services.prometheus = {
    enable = true;
    port = 9002;

    scrapeConfigs = [
      {
        job_name = "thrud";
        scrape_interval = "1s";
        static_configs = [{
          targets = [ "127.0.0.1:9091" ];
          # interval = "1s";
        }];
      }
      {
        job_name = "order-killer";
        scrape_interval = "1s";
        static_configs = [{
          targets = [ "127.0.0.1:8081" ];
          # interval = "1s";
        }];
      }
    ];
  };

}
