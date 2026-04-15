{ config, pkgs, lib, ... }: {

  # OpenTelemetry Collector: receives OTLP from Claude Code, exports to Prometheus
  services.opentelemetry-collector = {
    enable = true;
    package = pkgs.opentelemetry-collector-contrib;
    settings = {
      receivers.otlp.protocols = {
        grpc.endpoint = "0.0.0.0:4317";
        http.endpoint = "0.0.0.0:4318";
      };
      processors = {
        memory_limiter = {
          check_interval = "1s";
          limit_mib = 512;
        };
        batch = {
          timeout = "1s";
          send_batch_size = 1024;
        };
      };
      exporters = {
        prometheus = {
          endpoint = "127.0.0.1:8889";
          resource_to_telemetry_conversion.enabled = true;
        };
        debug.verbosity = "basic";
      };
      service.pipelines = {
        metrics = {
          receivers = [ "otlp" ];
          processors = [ "memory_limiter" "batch" ];
          exporters = [ "prometheus" ];
        };
        logs = {
          receivers = [ "otlp" ];
          processors = [ "memory_limiter" "batch" ];
          exporters = [ "debug" ];
        };
      };
    };
  };

  # Prometheus: scrapes eink-bridge server on amd-pc + pushgateway for Android/CLI
  services.prometheus = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 9090;

    pushgateway = {
      enable = true;
      web.listen-address = "0.0.0.0:9091";
    };

    rules = [''
      groups:
        - name: claude_code
          interval: 1m
          rules:
            - record: claude_code:cost_usd:total
              expr: sum by (project_name) (max_over_time(claude_code_cost_usage_USD_total[10m]))
            - record: claude_code:tokens:total
              expr: sum by (project_name) (max_over_time(claude_code_token_usage_tokens_total[10m]))
            - record: claude_code:cost_usd:by_model
              expr: sum by (model) (max_over_time(claude_code_cost_usage_USD_total[10m]))
    ''];

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
      {
        job_name = "claude-code";
        honor_labels = true;
        scrape_interval = "60s";
        static_configs = [{
          targets = [ "127.0.0.1:8889" ];
          labels.instance = "otelcol";
        }];
      }
    ];
  };

  # Grafana: dashboards for eink-bridge metrics
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3002;
        domain = "grafana.house.flakm.com";
        root_url = "https://grafana.house.flakm.com/";
      };
      security = {
        cookie_secure = true;
        csrf_trusted_origins = "grafana.house.flakm.com";
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

  services.nginx.virtualHosts."grafana.house.flakm.com" = {
    useACMEHost = "house.flakm.com";
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:3002";
      proxyWebsockets = true;
    };
  };

  # Open ports for LAN access
  networking.firewall.allowedTCPPorts = [
    9090  # Prometheus (useful for debugging)
    9091  # Pushgateway (Android + CLI push targets)
    4317  # OTLP gRPC
    4318  # OTLP HTTP
  ];
}
