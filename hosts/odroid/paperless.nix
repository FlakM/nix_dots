{ config, pkgs, ... }: {
  nixpkgs.overlays = [
    (self: super: {
      paperless-ngx = super.paperless-ngx.overrideAttrs (old: {
        doCheck = false;
      });
    })
  ];

  sops.defaultSopsFile = ../../secrets/secrets.yaml;
  sops.secrets = {
    paperless_admin_password = {
      restartUnits = [ "paperless-scheduler.service" "paperless-consumer.service" "paperless-web.service" ];
      mode = "0440";
      owner = "paperless";
    };
    paperless_secret_key = {
      restartUnits = [ "paperless-scheduler.service" "paperless-consumer.service" "paperless-web.service" ];
      mode = "0440";
      owner = "paperless";
    };
    paperless_api_token = {
      restartUnits = [ "podman-paperless-ai.service" ];
      mode = "0440";
      owner = "root";
    };
    paperless_openai_api_key = {
      key = "open_api_key";
      restartUnits = [ "podman-paperless-ai.service" ];
      mode = "0440";
      owner = "root";
    };
    gmail_oauth_client_id = {
      restartUnits = [ "paperless-scheduler.service" "paperless-consumer.service" "paperless-web.service" ];
      mode = "0440";
      owner = "paperless";
    };
    gmail_oauth_client_secret = {
      restartUnits = [ "paperless-scheduler.service" "paperless-consumer.service" "paperless-web.service" ];
      mode = "0440";
      owner = "paperless";
    };
  };

  services.paperless = {
    enable = true;
    address = "127.0.0.1";
    port = 28981;
    dataDir = "/var/lib/paperless";
    consumptionDirIsPublic = true;
    passwordFile = config.sops.secrets.paperless_admin_password.path;
    
    settings = {
      PAPERLESS_URL = "https://paperless.house.flakm.com";
      PAPERLESS_ALLOWED_HOSTS = "paperless.house.flakm.com,localhost,127.0.0.1";
      PAPERLESS_CORS_ALLOWED_HOSTS = "https://paperless.house.flakm.com";
      
      # OCR and language settings
      PAPERLESS_OCR_LANGUAGE = "eng+pol";
      PAPERLESS_OCR_USER_ARGS = {
        optimize = 1;
        pdfa_image_compression = "lossless";
      };
      
      # Security settings
      PAPERLESS_SECRET_KEY_FILE = config.sops.secrets.paperless_secret_key.path;
      PAPERLESS_STATIC_URL = "/static/";
      
      # Database configuration (using PostgreSQL)
      PAPERLESS_DBENGINE = "postgresql";
      PAPERLESS_DBHOST = "/run/postgresql";
      PAPERLESS_DBNAME = "paperless";
      PAPERLESS_DBUSER = "paperless";
      
      # Redis configuration
      PAPERLESS_REDIS = "redis://localhost:6379";
      
      # Consumer settings
      PAPERLESS_CONSUMER_POLLING = 30;
      PAPERLESS_CONSUMER_IGNORE_PATTERN = [
        ".DS_STORE/*"
        "desktop.ini"
        "Thumbs.db"
        "._*"
      ];
      
      # Task processing
      PAPERLESS_TASK_WORKERS = 2;
      PAPERLESS_THREADS_PER_WORKER = 1;
      
      # Tika settings for better text extraction
      PAPERLESS_TIKA_ENABLED = true;
      PAPERLESS_TIKA_ENDPOINT = "http://localhost:9998";
      PAPERLESS_TIKA_GOTENBERG_ENDPOINT = "http://localhost:3010";
      
      # Time zone
      PAPERLESS_TIME_ZONE = "Europe/Warsaw";
      
      # Gmail OAuth configuration
      PAPERLESS_OAUTH_CALLBACK_BASE_URL = "https://paperless.house.flakm.com";
      PAPERLESS_GMAIL_OAUTH_CLIENT_ID_FILE = config.sops.secrets.gmail_oauth_client_id.path;
      PAPERLESS_GMAIL_OAUTH_CLIENT_SECRET_FILE = config.sops.secrets.gmail_oauth_client_secret.path;
    };
  };

  # PostgreSQL database setup
  services.postgresql = {
    ensureDatabases = [ "paperless" ];
    ensureUsers = [{
      name = "paperless";
      ensureDBOwnership = true;
    }];
  };

  # Redis for task queue
  services.redis.servers.paperless = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
  };

  # Tika server for document processing
  services.tika = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9998;
  };

  # Gotenberg for PDF processing
  virtualisation.oci-containers.containers.gotenberg = {
    image = "gotenberg/gotenberg:8";
    ports = [ "127.0.0.1:3010:3000" ];
    cmd = [
      "gotenberg"
      "--chromium-disable-javascript=true"
      "--chromium-allow-list=file:///tmp/.*"
    ];
  };

  # Paperless-AI for document analysis and tagging
  virtualisation.oci-containers.containers.paperless-ai = {
    image = "clusterzx/paperless-ai:latest";
    ports = [ "127.0.0.1:3011:3000" ];
    volumes = [
      "paperless-ai-data:/app/data"
      "${config.sops.secrets.paperless_openai_api_key.path}:/run/secrets/openai_api_key:ro"
      "${config.sops.secrets.paperless_api_token.path}:/run/secrets/paperless_api_token:ro"
    ];
    environment = {
      PAPERLESS_AI_PORT = "3000";
    };
    extraOptions = [
      "--add-host=host.containers.internal:host-gateway"
    ];
  };

  # Enable container runtime
  virtualisation.oci-containers.backend = "podman";
  virtualisation.podman.enable = true;

  # Nginx reverse proxy configuration
  services.nginx.virtualHosts."paperless.house.flakm.com" = {
    useACMEHost = "house.flakm.com";
    forceSSL = true;
    
    locations."/" = {
      proxyPass = "http://127.0.0.1:28981";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Server $host;
        
        client_max_body_size 100M;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
      '';
    };
  };

  # Nginx configuration for Paperless-AI interface
  services.nginx.virtualHosts."paperless-ai.house.flakm.com" = {
    useACMEHost = "house.flakm.com";
    forceSSL = true;
    
    locations."/" = {
      proxyPass = "http://127.0.0.1:3011";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Server $host;
        
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
      '';
    };
  };

  # Open firewall for internal access
  networking.firewall.allowedTCPPorts = [ 28981 ];
}
