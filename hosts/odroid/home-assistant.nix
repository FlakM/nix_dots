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
  phoneNotificationActions = notification: [
    {
      action = "notify.mobile_app_pixel_10a";
      data = notification;
    }
    {
      "if" = [
        {
          condition = "template";
          value_template = "{{ not is_state('device_tracker.pixel_10a_2', 'home') }}";
        }
      ];
      "then" = [
        {
          action = "notify.mobile_app_sm_s921b";
          data = notification;
        }
      ];
    }
  ];
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
    lovelaceConfig = {
      title = "Camera controls";
      views = [
        {
          title = "Camera alerts";
          path = "camera-alerts";
          icon = "mdi:cctv";
          cards = [
            {
              type = "horizontal-stack";
              cards = [
                {
                  type = "button";
                  name = "Silence for 30 min";
                  icon = "mdi:bell-sleep";
                  tap_action = {
                    action = "perform-action";
                    perform_action = "script.camera_alerts_snooze_30m";
                  };
                }
                {
                  type = "button";
                  name = "Resume alerts";
                  icon = "mdi:bell-ring";
                  tap_action = {
                    action = "perform-action";
                    perform_action = "script.camera_alerts_resume";
                  };
                }
              ];
            }
            {
              type = "entities";
              title = "Status";
              entities = [ "timer.camera_alerts_snooze" ];
            }
          ];
        }
      ];
    };
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
      timer.camera_alerts_snooze = {
        name = "Camera alerts snooze";
        duration = "00:30:00";
        restore = true;
        icon = "mdi:bell-sleep";
      };
      script = {
        camera_alerts_snooze_30m = {
          alias = "Silence camera alerts for 30 minutes";
          icon = "mdi:bell-sleep";
          mode = "restart";
          sequence = [
            {
              action = "timer.start";
              target.entity_id = "timer.camera_alerts_snooze";
              data.duration = "00:30:00";
            }
          ];
        };
        camera_alerts_resume = {
          alias = "Resume camera alerts";
          icon = "mdi:bell-ring";
          sequence = [
            {
              action = "timer.cancel";
              target.entity_id = "timer.camera_alerts_snooze";
            }
          ];
        };
      };
      lovelace.dashboards.nixos-lovelace = {
        mode = "yaml";
        filename = "ui-lovelace.yaml";
        title = "Camera controls";
        icon = "mdi:cctv";
        show_in_sidebar = true;
      };
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
          conditions = [
            {
              condition = "state";
              entity_id = "timer.camera_alerts_snooze";
              state = "idle";
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
          actions = phoneNotificationActions {
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
              actions = [
                {
                  action = "SNOOZE_CAMERA_ALERTS_30M";
                  title = "Silence for 30 min";
                }
              ];
            };
          };
        }
        {
          id = "lionelo_onboard_motion_alert";
          alias = "Lionelo onboard motion alert";
          mode = "parallel";
          max = 10;
          triggers = [
            {
              trigger = "mqtt";
              topic = "lionelo/babyline/events";
            }
          ];
          conditions = [
            {
              condition = "state";
              entity_id = "timer.camera_alerts_snooze";
              state = "idle";
            }
          ];
          actions = phoneNotificationActions {
            title = "{{ trigger.payload_json.title }}";
            message = "{{ trigger.payload_json.message }}";
            data = {
              image = "{{ trigger.payload_json.image_url }}";
              clickAction = "https://frigate.house.flakm.com/";
              tag = "lionelo-onboard-motion";
              group = "camera-alerts";
              channel = "Camera alerts";
              notification_icon = "mdi:motion-sensor";
              ttl = 0;
              priority = "high";
              actions = [
                {
                  action = "SNOOZE_CAMERA_ALERTS_30M";
                  title = "Silence for 30 min";
                }
              ];
            };
          };
        }
        {
          id = "camera_alert_snooze_commands";
          alias = "Camera alert snooze commands";
          mode = "restart";
          triggers = [
            {
              trigger = "event";
              event_type = "mobile_app_notification_action";
              event_data.action = "SNOOZE_CAMERA_ALERTS_30M";
            }
            {
              trigger = "mqtt";
              topic = "home/camera-alerts/snooze/set";
              payload = "30";
            }
          ];
          actions = [
            {
              action = "script.camera_alerts_snooze_30m";
            }
          ];
        }
        {
          id = "camera_alert_resume_command";
          alias = "Camera alert resume command";
          triggers = [
            {
              trigger = "mqtt";
              topic = "home/camera-alerts/snooze/set";
              payload = "0";
            }
          ];
          actions = [
            {
              action = "script.camera_alerts_resume";
            }
          ];
        }
        {
          id = "camera_alert_snooze_state";
          alias = "Publish camera alert snooze state";
          triggers = [
            {
              trigger = "state";
              entity_id = "timer.camera_alerts_snooze";
            }
            {
              trigger = "homeassistant";
              event = "start";
            }
          ];
          actions = [
            {
              action = "mqtt.publish";
              data = {
                topic = "home/camera-alerts/snooze/state";
                payload = "{{ 'ON' if is_state('timer.camera_alerts_snooze', 'active') else 'OFF' }}";
                qos = 1;
                retain = true;
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
