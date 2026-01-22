{ config, pkgs, lib, ... }:
{
  services.home-assistant = {
    enable = true;
    extraComponents = [
      "default_config"
      "met"
      "radio_browser"
      "isal"
      # network/system integrations
      "adguard"
      "uptime_kuma"
      "netdata"
      # media integrations
      "jellyfin"
      # device integrations
      "lg_webos_tv"
      "brother"
      "xiaomi_miio"
      "xiaomi_ble"
      # protocols
      "bluetooth"
      "esphome"
      "mqtt"
      # utility
      "backup"
    ];
    extraPackages = ps: with ps; [
      psycopg2
    ];
    config = {
      homeassistant = {
        name = "Home";
        unit_system = "metric";
        temperature_unit = "C";
        time_zone = "Europe/Warsaw";
        country = "PL";
        internal_url = "http://127.0.0.1:8123";
        external_url = "https://homeassistant.house.flakm.com";
      };
      http = {
        server_port = 8123;
        use_x_forwarded_for = true;
        trusted_proxies = [ "127.0.0.1" "::1" ];
      };
      recorder = {
        db_url = "postgresql://@/hass";
        purge_keep_days = 30;
      };
      logger = {
        default = "info";
      };
    };
  };

  systemd.services.home-assistant = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
  };

  services.nginx.virtualHosts."homeassistant.house.flakm.com" = {
    useACMEHost = "house.flakm.com";
    forceSSL = true;
    extraConfig = ''
      proxy_buffering off;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:8123";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };
}
