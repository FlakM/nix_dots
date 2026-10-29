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
  # The upstream integration only serves/registers this standalone frontend file.
  # NixOS customLovelaceModules does both, without HACS or a custom Python backend.
  wledControlCard = pkgs.runCommand "wled-control-card-1.4.5" {
    pname = "wled-control-card";
    version = "1.4.5";
    src = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/Si-Al-Ri/wled-control-card/de5dee3df44466c1345746676202d124322c986b/custom_components/wled_control_card/dist/wled-control-card.js";
      hash = "sha256-OtYjgfBQDLFc4Yp6Ha3SwtgZtVk3roMbIqtREIEKcpU=";
    };
  } ''
    install -Dm444 "$src" "$out/wled-control-card.js"
  '';
  kitchenLight = "light.kuchnia_blat_b";
  kitchenDashboard = (pkgs.formats.yaml { }).generate "kitchen-lighting.yaml" {
    title = "Kuchnia";
    views = [
      {
        title = "Blat B";
        path = "blat-b";
        icon = "mdi:led-strip-variant";
        cards = [
          {
            type = "conditional";
            conditions = [
              { condition = "state"; entity = kitchenLight; state = "unknown"; }
            ];
            card = {
              type = "markdown";
              content = ''
                ## Dodaj oświetlenie blatu B

                1. Włącz sprawdzony zestaw WLED i ustal jego aktualny adres IP.
                2. W **Ustawienia → Urządzenia i usługi → Dodaj integrację → WLED**
                   dodaj kontroler o MAC **88:57:21:B1:A2:DC**.
                   Ostatni znany adres to **192.168.0.4** — sprawdź go przed dodaniem.
                3. Przypisz urządzenie do obszaru **Kuchnia**, nazwij **Kuchnia blat B**
                   i ustaw identyfikator głównej encji światła na `${kitchenLight}`.

                Tylko strefa B. Bez harmonogramów i automatycznego włączania.
                Przycisk IO33 działa lokalnie, niezależnie od Home Assistanta.
              '';
            };
          }
          {
            type = "conditional";
            conditions = [
              { condition = "state"; entity = kitchenLight; state_not = "unknown"; }
            ];
            card = {
              type = "custom:wled-control-card";
              entity = kitchenLight;
              name = "Blat B";
              show_segments = false;
              show_brightness = true;
              show_color_pickers = true;
              show_favorites = false;
              show_favorite_presets = true;
              favorite_presets = [ ];
              show_presets = true;
              show_palettes = false;
              show_playlist = false;
              show_effects = false;
              show_speed = false;
              show_intensity = false;
              dynamic_brightness_color = true;
              extra_controls = [ ];
            };
          }
          {
            type = "conditional";
            conditions = [
              { condition = "state"; entity = kitchenLight; state = "unavailable"; }
            ];
            card = {
              type = "markdown";
              content = "**Brak połączenia ze strefą B.** Sprawdź zasilanie kontrolera, Wi-Fi i jego aktualny adres IP. Podczas montażu pozostaw zasilacz odłączony.";
            };
          }
          {
            type = "markdown";
            content = ''
              **Pierwsze uruchomienie:** zacznij od małej jasności na sprawdzonym zestawie.
              Nie zwiększaj limitu prądu przed doborem zabezpieczenia i próbą całej taśmy w profilu.
              RGB+CCT ma ograniczenia sterowania w HA; presety bieli dodamy po ich sprawdzeniu w WLED.
            '';
          }
        ];
      }
      {
        title = "Podstawowe";
        path = "podstawowe";
        icon = "mdi:lightbulb-outline";
        cards = [
          {
            type = "markdown";
            content = "Podstawowe sterowanie B, bez zależności od dodatkowej karty WLED. Jeśli światło nie zostało jeszcze dodane, skorzystaj z instrukcji w zakładce **Blat B**.";
          }
          {
            type = "conditional";
            conditions = [
              { condition = "state"; entity = kitchenLight; state_not = "unknown"; }
            ];
            card = {
              type = "tile";
              entity = kitchenLight;
              name = "Blat B";
              icon = "mdi:led-strip-variant";
              tap_action.action = "more-info";
              icon_tap_action.action = "toggle";
              features = [ { type = "light-brightness"; } ];
            };
          }
        ];
      }
    ];
  };
  frigateComponent = pkgs.home-assistant-custom-components.frigate.overridePythonAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./frigate-notification-auth.patch ];
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
  imports = [
    (import ./camera-notifications.nix { inherit phoneNotificationActions; })
    ./smart-plugs.nix
  ];
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
    openFirewall = true;
    package = homeAssistantPackage;
    customLovelaceModules = [ wledControlCard ];
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
              entities = [ "timer.camera_alerts_snooze" "timer.camera_alerts_snooze_cars" "binary_sensor.frigate_service_healthy" "binary_sensor.frigate_detector_healthy" "sensor.frigate_recording_space_free" ];
            }
          ];
        }
      ] ++ map
        (camera: {
          title = builtins.replaceStrings [ "_" ] [ " " ] camera;
          path = "camera-${camera}";
          icon = "mdi:cctv";
          cards = [
            { type = "picture-entity"; entity = "camera.${camera}"; camera_view = "live"; show_state = false; }
            {
              type = "horizontal-stack";
              cards = [
                { type = "button"; name = "Mute this camera 30 min"; icon = "mdi:bell-sleep"; tap_action = { action = "perform-action"; perform_action = "script.camera_alerts_snooze_camera"; data.camera_id = camera; }; }
                { type = "button"; name = "Resume this camera"; icon = "mdi:bell-ring"; tap_action = { action = "perform-action"; perform_action = "script.camera_alerts_resume_camera"; data.camera_id = camera; }; }
                { type = "button"; name = "Mute cars 30 min"; icon = "mdi:car-off"; tap_action = { action = "perform-action"; perform_action = "script.camera_alerts_snooze_cars"; }; }
              ];
            }
            { type = "entities"; entities = [ "timer.camera_alerts_snooze_${camera}" "timer.camera_alerts_snooze_cars" "binary_sensor.frigate_${camera}_stream_healthy" ]; }
          ];
        }) [ "front_left" "front_right" "back" "babyline" ];
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
      "wled"
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
        internal_url = "http://192.168.0.102:8123";
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
              target.entity_id = [ "timer.camera_alerts_snooze" "timer.camera_alerts_snooze_cars" "timer.camera_alerts_snooze_front_left" "timer.camera_alerts_snooze_front_right" "timer.camera_alerts_snooze_back" "timer.camera_alerts_snooze_babyline" ];
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
      lovelace.dashboards.kitchen-lighting = {
        mode = "yaml";
        filename = "${kitchenDashboard}";
        title = "Kuchnia";
        icon = "mdi:led-strip-variant";
        show_in_sidebar = true;
      };
      automation = [
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
            { condition = "state"; entity_id = "timer.camera_alerts_snooze_babyline"; state = "idle"; }
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
