{ phoneNotificationActions }:
{ lib, ... }:
let
  cameras = [ "front_left" "front_right" "back" "babyline" ];
  timerFor = camera: "camera_alerts_snooze_${camera}";
  notifyActivity = phoneNotificationActions {
    title = "{{ notification_title }}";
    message = "{{ notification_message }}";
    data = {
      image = "{{ image_url }}";
      clickAction = "{{ clip_url }}";
      tag = "{{ notification_tag }}";
      group = "camera-alerts";
      channel = "{{ 'Cars' if object_label == 'car' else 'People' }}";
      notification_icon = "{{ 'mdi:car' if object_label == 'car' else 'mdi:account' }}";
      ttl = 0;
      priority = "high";
      alert_once = true;
      actions = [
        { action = "URI"; title = "View clip"; uri = "{{ clip_url }}"; }
        { action = "URI"; title = "Live camera"; uri = "https://homeassistant.house.flakm.com/nixos-lovelace/camera-{{ camera_id }}"; }
        {
          action = "{{ 'SNOOZE_CAMERA_CARS_30M' if object_label == 'car' else 'SNOOZE_CAMERA_' ~ camera_id ~ '_30M' }}";
          title = "{{ 'Mute cars 30 min' if object_label == 'car' else 'Mute camera 30 min' }}";
        }
      ];
    };
  };
  notSnoozed = [
    { condition = "state"; entity_id = "timer.camera_alerts_snooze"; state = "idle"; }
    {
      condition = "template";
      value_template = "{{ is_state('timer.camera_alerts_snooze_' ~ camera_id, 'idle') and (object_label != 'car' or is_state('timer.camera_alerts_snooze_cars', 'idle')) }}";
    }
  ];
  healthSensors = map
    (camera: {
      name = "Frigate ${camera} stream healthy";
      unique_id = "frigate_${camera}_stream_healthy";
      state_topic = "frigate/stats";
      value_template = "{{ 'ON' if value_json.cameras['${camera}'].camera_fps > 0 else 'OFF' }}";
      payload_on = "ON";
      payload_off = "OFF";
      expire_after = 180;
      device_class = "connectivity";
      availability_topic = "frigate/available";
      payload_available = "online";
      payload_not_available = "offline";
    })
    cameras;
  healthEntities = map (camera: "binary_sensor.frigate_${camera}_stream_healthy") cameras;
  healthFlag = entity: "camera_health_${builtins.replaceStrings [ "." ] [ "_" ] entity}";
in
{
  services.home-assistant.config = {
    input_text = lib.genAttrs [ "frigate_car_arrivals_notified" "frigate_car_departures_notified" ] (_: {
      max = 255;
      icon = "mdi:car";
    });
    input_boolean = lib.genAttrs (map healthFlag (healthEntities ++ [ "binary_sensor.frigate_service_healthy" "binary_sensor.frigate_detector_healthy" "sensor.frigate_recording_space_free" ])) (_: { icon = "mdi:cctv"; });
    timer = lib.genAttrs (map timerFor cameras ++ [ "camera_alerts_snooze_cars" ]) (_: {
      duration = "00:30:00";
      restore = true;
      icon = "mdi:bell-sleep";
    });
    script = {
      camera_alerts_snooze_camera = {
        alias = "Mute one camera for 30 minutes";
        mode = "parallel";
        fields.camera_id = {
          required = true;
          selector.select.options = cameras;
        };
        sequence = [{
          action = "timer.start";
          target.entity_id = "{{ 'timer.camera_alerts_snooze_' ~ camera_id }}";
          data.duration = "00:30:00";
        }];
      };
      camera_alerts_resume_camera = {
        alias = "Resume one camera's alerts";
        mode = "parallel";
        fields.camera_id = {
          required = true;
          selector.select.options = cameras;
        };
        sequence = [{
          action = "timer.cancel";
          target.entity_id = "{{ 'timer.camera_alerts_snooze_' ~ camera_id }}";
        }];
      };
      camera_alerts_snooze_cars = {
        alias = "Mute cars for 30 minutes";
        mode = "restart";
        sequence = [{
          action = "timer.start";
          target.entity_id = "timer.camera_alerts_snooze_cars";
          data.duration = "00:30:00";
        }];
      };
    };
    mqtt = {
      binary_sensor = healthSensors ++ [
        {
          name = "Frigate service healthy";
          unique_id = "frigate_service_healthy";
          state_topic = "frigate/available";
          payload_on = "online";
          payload_off = "offline";
          device_class = "connectivity";
        }
        {
          name = "Frigate detector healthy";
          unique_id = "frigate_detector_healthy";
          state_topic = "frigate/stats";
          value_template = "{{ 'ON' if value_json.detectors.openvino.inference_speed > 0 and (value_json.detectors.openvino.detection_start == 0 or as_timestamp(now()) - value_json.detectors.openvino.detection_start < 60) else 'OFF' }}";
          payload_on = "ON";
          payload_off = "OFF";
          expire_after = 180;
          device_class = "connectivity";
        }
      ];
      sensor = [{
        name = "Frigate recording space free";
        unique_id = "frigate_recording_space_free";
        state_topic = "frigate/stats";
        value_template = "{{ (value_json.service.storage['/var/lib/frigate/recordings'].free / 1024) | round(1) }}";
        unit_of_measurement = "GiB";
        device_class = "data_size";
        state_class = "measurement";
        expire_after = 180;
      }];
    };
    automation = [
      {
        id = "frigate_person_alert";
        alias = "Frigate confirmed person alerts";
        mode = "queued";
        max = 30;
        triggers = [{ trigger = "mqtt"; topic = "frigate/reviews"; }];
        variables = {
          camera_id = "{{ trigger.payload_json.after.camera }}";
          object_label = "person";
          event_id = "{{ trigger.payload_json.after.data.detections | first | default('') }}";
          notification_tag = "frigate-review-{{ trigger.payload_json.after.id }}";
          notification_title = "Person detected";
          notification_message = "{{ camera_id | replace('_', ' ') | title }}: confirmed person activity.";
          image_url = "/api/frigate/notifications/{{ trigger.payload_json.after.id }}/{{ camera_id }}/review_thumbnail.webp?v={{ trigger.payload_json.after.data.thumb_time | default(trigger.payload_json.after.start_time) }}{{ '-end' if trigger.payload_json.type == 'end' else '' }}";
          clip_url = "https://homeassistant.house.flakm.com/api/frigate/notifications/{{ trigger.payload_json.after.data.detections | first | default('') }}/clip.mp4";
        };
        conditions = [{
          condition = "template";
          value_template = "{{ camera_id in ['front_left', 'front_right', 'back'] and trigger.payload_json.after.severity == 'alert' and 'person' in trigger.payload_json.after.data.objects and event_id != '' }}";
        }] ++ notSnoozed;
        actions = notifyActivity;
      }
      {
        id = "frigate_driveway_car_transitions";
        alias = "Frigate driveway car arrivals and departures";
        mode = "queued";
        max = 30;
        trace.stored_traces = 30;
        triggers = [{ trigger = "mqtt"; topic = "frigate/events"; }];
        variables = {
          arrival_ids = "{{ states('input_text.frigate_car_arrivals_notified').removeprefix('ids:').split(',') | reject('in', ['', 'unknown', 'unavailable']) | list }}";
          camera_id = "{{ trigger.payload_json.after.camera }}";
          departure_ids = "{{ states('input_text.frigate_car_departures_notified').removeprefix('ids:').split(',') | reject('in', ['', 'unknown', 'unavailable']) | list }}";
          object_label = "car";
          event_id = "{{ trigger.payload_json.after.id }}";
          inside_before = "{{ 'podjazd_prawy' in trigger.payload_json.before.current_zones | default([]) }}";
          inside_after = "{{ 'podjazd_prawy' in trigger.payload_json.after.current_zones | default([]) }}";
          moving = "{{ trigger.payload_json.after.get('active', not trigger.payload_json.after.get('stationary', false)) }}";
          notification_tag = "frigate-car-{{ event_id }}";
          notification_title = "{{ 'Car left' if (event_id in departure_ids if trigger.payload_json.type == 'end' else not inside_after) else 'Car arrived' }}";
          notification_message = "{{ 'Car left the right driveway.' if (event_id in departure_ids if trigger.payload_json.type == 'end' else not inside_after) else 'Car entered the right driveway.' }}";
          image_url = "/api/frigate/notifications/{{ event_id }}/snapshot.jpg?v={{ (trigger.payload_json.after.get('snapshot') or {}).get('frame_time', trigger.payload_json.after.frame_time) }}{{ '-end' if trigger.payload_json.type == 'end' else '' }}";
          clip_url = "https://homeassistant.house.flakm.com/api/frigate/notifications/{{ trigger.payload_json.after.id }}/clip.mp4";
        };
        conditions = [{
          condition = "template";
          value_template = "{{ camera_id == 'front_right' and trigger.payload_json.after.label == 'car' and not trigger.payload_json.after.false_positive and ((trigger.payload_json.type == 'update' and moving and ((not inside_before and inside_after and event_id not in arrival_ids and event_id not in departure_ids) or (inside_before and not inside_after and event_id not in departure_ids))) or (trigger.payload_json.type == 'end' and (event_id in arrival_ids or event_id in departure_ids))) }}";
        }] ++ notSnoozed;
        actions = [
          {
            condition = "template";
            value_template = "{{ trigger.payload_json.type == 'end' or ((inside_after and event_id not in states('input_text.frigate_car_arrivals_notified').removeprefix('ids:').split(',') and event_id not in states('input_text.frigate_car_departures_notified').removeprefix('ids:').split(',')) or (not inside_after and event_id not in states('input_text.frigate_car_departures_notified').removeprefix('ids:').split(','))) }}";
          }
          {
            choose = [
              {
                conditions = [{ condition = "template"; value_template = "{{ trigger.payload_json.type == 'update' and inside_after }}"; }];
                sequence = [{
                  action = "input_text.set_value";
                  target.entity_id = "input_text.frigate_car_arrivals_notified";
                  data.value = "ids:{{ ([event_id] + (states('input_text.frigate_car_arrivals_notified').removeprefix('ids:').split(',') | reject('in', ['', 'unknown', 'unavailable', event_id]) | list))[:8] | join(',') }}";
                }];
              }
              {
                conditions = [{ condition = "template"; value_template = "{{ trigger.payload_json.type == 'update' and not inside_after }}"; }];
                sequence = [{
                  action = "input_text.set_value";
                  target.entity_id = "input_text.frigate_car_departures_notified";
                  data.value = "ids:{{ ([event_id] + (states('input_text.frigate_car_departures_notified').removeprefix('ids:').split(',') | reject('in', ['', 'unknown', 'unavailable', event_id]) | list))[:8] | join(',') }}";
                }];
              }
            ];
          }
        ] ++ notifyActivity;
      }
      {
        id = "camera_alert_selective_snooze";
        alias = "Selective camera notification snooze";
        mode = "parallel";
        triggers = [{ trigger = "event"; event_type = "mobile_app_notification_action"; }];
        conditions = [{
          condition = "template";
          value_template = "{{ trigger.event.data.action in ['SNOOZE_CAMERA_CARS_30M', 'SNOOZE_CAMERA_front_left_30M', 'SNOOZE_CAMERA_front_right_30M', 'SNOOZE_CAMERA_back_30M', 'SNOOZE_CAMERA_babyline_30M'] }}";
        }];
        actions = [{
          choose = [{
            conditions = [{ condition = "template"; value_template = "{{ trigger.event.data.action == 'SNOOZE_CAMERA_CARS_30M' }}"; }];
            sequence = [{ action = "script.camera_alerts_snooze_cars"; }];
          }];
          default = [{
            action = "script.camera_alerts_snooze_camera";
            data.camera_id = "{{ trigger.event.data.action | replace('SNOOZE_CAMERA_', '') | replace('_30M', '') }}";
          }];
        }];
      }
      {
        id = "frigate_monitoring_health";
        alias = "Frigate monitoring health and recovery";
        mode = "parallel";
        max = 10;
        triggers = [
          { trigger = "state"; entity_id = healthEntities ++ [ "binary_sensor.frigate_service_healthy" "binary_sensor.frigate_detector_healthy" ]; to = [ "off" "unavailable" ]; for.minutes = 2; id = "failure"; }
          { trigger = "state"; entity_id = healthEntities ++ [ "binary_sensor.frigate_service_healthy" "binary_sensor.frigate_detector_healthy" ]; from = [ "off" "unavailable" "unknown" ]; to = "on"; for.seconds = 30; id = "recovery"; }
          { trigger = "numeric_state"; entity_id = "sensor.frigate_recording_space_free"; below = 100; for.minutes = 5; id = "storage_low"; }
          { trigger = "numeric_state"; entity_id = "sensor.frigate_recording_space_free"; above = 150; for.minutes = 5; id = "storage_recovered"; }
        ];
        variables.problem_flag = "{{ 'input_boolean.camera_health_' ~ (trigger.entity_id | replace('.', '_')) }}";
        conditions = [{
          condition = "template";
          value_template = "{{ is_state(problem_flag, 'off') if trigger.id in ['failure', 'storage_low'] else is_state(problem_flag, 'on') }}";
        }
          {
            condition = "template";
            value_template = "{{ trigger.id != 'failure' or trigger.entity_id == 'binary_sensor.frigate_service_healthy' or is_state('binary_sensor.frigate_service_healthy', 'on') }}";
          }];
        actions = [{
          action = "{{ 'input_boolean.turn_on' if trigger.id in ['failure', 'storage_low'] else 'input_boolean.turn_off' }}";
          target.entity_id = "{{ problem_flag }}";
        }] ++ phoneNotificationActions {
          title = "{{ 'Camera monitoring problem' if trigger.id in ['failure', 'storage_low'] else 'Camera monitoring recovered' }}";
          message = "{{ trigger.to_state.name }}: {{ trigger.to_state.state }}{{ ' GiB free' if trigger.entity_id == 'sensor.frigate_recording_space_free' else '' }}.";
          data = {
            tag = "frigate-health-{{ trigger.entity_id }}";
            channel = "Camera health";
            group = "camera-health";
            notification_icon = "mdi:cctv";
            clickAction = "https://homeassistant.house.flakm.com/nixos-lovelace/camera-alerts";
          };
        };
      }
    ];
  };
  services.nginx = {
    proxyCachePath.camera-snapshots = {
      enable = true;
      keysZoneName = "camera_snapshots";
      keysZoneSize = "8m";
      maxSize = "128m";
      inactive = "24h";
      levels = "1:2";
    };
    virtualHosts."homeassistant.house.flakm.com".locations."~ ^/api/frigate/notifications/[a-zA-Z0-9.-]+/(snapshot\\.jpg|thumbnail\\.jpg|[a-z_]+/review_thumbnail\\.webp)$" = {
      proxyPass = "http://127.0.0.1:8123";
      recommendedProxySettings = true;
      extraConfig = ''
        proxy_buffering on;
        proxy_cache camera_snapshots;
        proxy_cache_key "$scheme$host$request_uri";
        proxy_cache_valid 200 10s;
        proxy_cache_lock on;
        proxy_ignore_headers Cache-Control Expires;
        proxy_hide_header Cache-Control;
        add_header Cache-Control "private, max-age=10" always;
        add_header X-Snapshot-Cache $upstream_cache_status always;
      '';
    };
  };
}
