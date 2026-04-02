{ config, pkgs, lib, ... }: {

  # Prometheus: scrapes eink-bridge server on amd-pc + pushgateway for Android/CLI
  services.prometheus = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 9090;

    pushgateway = {
      enable = true;
      web.listen-address = "0.0.0.0:9091";
    };

    scrapeConfigs = [
      {
        job_name = "eink-bridge";
        scrape_interval = "15s";
        metrics_path = "/metrics";
        static_configs = [{
          targets = [ "amd-pc:3333" ];
          labels = {
            instance = "amd-pc";
            service = "eink-bridge";
          };
        }];
      }
      {
        job_name = "pushgateway";
        honor_labels = true;
        scrape_interval = "30s";
        static_configs = [{
          targets = [ "127.0.0.1:9091" ];
          labels.instance = "pushgateway";
        }];
      }
    ];
  };

  # Grafana: dashboards for eink-bridge metrics
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3002;
        domain = "odroid";
        root_url = "http://odroid:3002/";
      };
      # allow anonymous read-only access for home lab convenience
      "auth.anonymous" = {
        enabled = true;
        org_role = "Viewer";
      };
    };

    provision = {
      enable = true;

      datasources.settings.datasources = [
        {
          name = "Prometheus";
          uid = "prometheus-eink";
          type = "prometheus";
          url = "http://127.0.0.1:9090";
          isDefault = true;
          access = "proxy";
        }
      ];

      dashboards.settings.providers = [
        {
          name = "eink-bridge";
          type = "file";
          disableDeletion = true;
          options.path = ./grafana-dashboards;
        }
      ];
    };
  };

  # Open ports for LAN access
  networking.firewall.allowedTCPPorts = [
    3002  # Grafana
    9090  # Prometheus (useful for debugging)
    9091  # Pushgateway (Android + CLI push targets)
  ];
}
