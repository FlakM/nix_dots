{ config, pkgs, lib, ... }:
let
  patchHomeAssistant = package: package.overridePythonAttrs (old: {
    disabledTests = (old.disabledTests or [ ]) ++ [
      "test_multiple_runs_repeat_choose"
      "test_immediate_works_with_schedule_call"
      "test_remove_refresh_token"
      "test_one_long_lived_access_token_per_refresh_token"
      "test_access_token_with_empty_key"
      "test_webhook_create_cloudhook_aborts_not_connected"
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
  sops.secrets = {
    omada_ha_username = {
      sopsFile = ../../secrets/secrets.yaml;
      owner = "hass";
    };
    omada_ha_password = {
      sopsFile = ../../secrets/secrets.yaml;
      owner = "hass";
    };
  };

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
      "tplink_omada"
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
      "automation"
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
        internal_url = "https://homeassistant.house.flakm.com";
        external_url = "https://homeassistant.house.flakm.com";
      };
      mobile_app = { };
      automation = [
        {
          id = "frigate_person_alert";
          alias = "Frigate person alert";
          mode = "parallel";
          max = 10;
          triggers = [
            {
              trigger = "state";
              entity_id = [
                "binary_sensor.podjazd_person_occupancy"
                "binary_sensor.ogrod_person_occupancy"
                "binary_sensor.podjazd_prawy_person_occupancy"
              ];
              from = "off";
              to = "on";
            }
          ];
          variables.camera_id = ''
            {% set cameras = {
              "binary_sensor.podjazd_person_occupancy": "front_left",
              "binary_sensor.ogrod_person_occupancy": "back",
              "binary_sensor.podjazd_prawy_person_occupancy": "front_right"
            } %}
            {{ cameras[trigger.entity_id] }}
          '';
          actions = [
            {
              action = "notify.mobile_app_pixel_7";
              data = {
                title = "Person detected";
                message = "{{ camera_id | replace('_', ' ') | title }} camera detected a person.";
                data = {
                  image = "/api/image_proxy/image.{{ camera_id }}_person";
                  clickAction = "https://frigate.house.flakm.com/review";
                  tag = "frigate-person-{{ camera_id }}";
                  group = "camera-alerts";
                  channel = "Camera alerts";
                  notification_icon = "mdi:cctv";
                  ttl = 0;
                  priority = "high";
                };
              };
            }
          ];
        }
      ];
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
