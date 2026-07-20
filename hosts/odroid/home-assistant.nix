{ config, pkgs, lib, ... }:
let
  patchHomeAssistant = package: package.overridePythonAttrs (old: {
    disabledTests = (old.disabledTests or [ ]) ++ [
      "test_remove_refresh_token"
      "test_one_long_lived_access_token_per_refresh_token"
      "test_access_token_with_empty_key"
      "test_multiple_runs_repeat_choose"
      "test_immediate_works_with_schedule_call"
    ];
  });
  homeAssistantPackage = (patchHomeAssistant pkgs.home-assistant) // {
    override = args: patchHomeAssistant (pkgs.home-assistant.override args);
  };
  frigateComponent = pkgs.home-assistant-custom-components.frigate.overridePythonAttrs (old: {
    doCheck = false;
    dependencies = map
      (dependency:
        if (dependency.pname or "") == "hass-web-proxy-lib" then
          dependency.overridePythonAttrs
            (_: {
              doCheck = false;
              passthru.tests = { };
              pythonImportsCheck = [ ];
            })
        else
          dependency)
      old.dependencies;
  });
in
{
  services.home-assistant = {
    enable = true;
    package = homeAssistantPackage;
    extraComponents = [
      "default_config"
      "met"
      "radio_browser"
      "isal"
      # discovery
      "ssdp"
      "zeroconf"
      "dhcp"
      "usb"
      # network/system integrations
      "adguard"
      "uptime_kuma"
      "netdata"
      # media integrations
      "jellyfin"
      # device integrations
      "webostv"
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
    customComponents = [ frigateComponent ];
    extraPackages = ps: with ps; [
      psycopg2
      gtts
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
