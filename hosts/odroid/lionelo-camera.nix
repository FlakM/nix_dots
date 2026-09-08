{ config, pkgs, ... }:
let
  aventproxy = pkgs.buildGoModule rec {
    pname = "avent-webrtc-bridge";
    version = "unstable-2026-08-31";

    src = pkgs.fetchFromGitHub {
      owner = "thekoma";
      repo = "aventproxy";
      rev = "d15a3117fdf8d0059f59cf451c9d8c0470e8a68a";
      hash = "sha256-BMR5Ysu6P+4VJB9PhA9j9cboWJ37/GVfys7XfMXdN/4=";
    };

    sourceRoot = "${src.name}/avent-webrtc-bridge";
    postPatch = ''
      substituteInPlace cmd/direct/direct.go \
        --replace-fail 'cmd.Flags().String("signing-key", "",' 'cmd.Flags().String("signing-key", os.Getenv("TUYA_SIGNING_KEY"),' \
        --replace-fail 'cmd.Flags().String("sid", "",' 'cmd.Flags().String("sid", os.Getenv("TUYA_SID"),' \
        --replace-fail 'cmd.Flags().String("ecode", "",' 'cmd.Flags().String("ecode", os.Getenv("TUYA_ECODE"),' \
        --replace-fail 'cmd.Flags().String("partner", "",' 'cmd.Flags().String("partner", os.Getenv("TUYA_PARTNER"),' \
        --replace-fail $'\tcmd.MarkFlagRequired("signing-key")\n' "" \
        --replace-fail $'\tcmd.MarkFlagRequired("sid")\n' "" \
        --replace-fail $'\tcmd.MarkFlagRequired("ecode")\n' "" \
        --replace-fail $'\tcmd.MarkFlagRequired("partner")\n' "" \
        --replace-fail $'\tcmd.Flags().String("ch-key", "071d81fa", "Channel key")\n' $'\tcmd.Flags().String("ch-key", "071d81fa", "Channel key")\n\tcmd.Flags().String("ttid", "", "Tuya app TTID")\n\tcmd.Flags().String("app-version", "1.8.0", "Tuya app version")\n' \
        --replace-fail $'\tchKey, _ := cmd.Flags().GetString("ch-key")\n' $'\tchKey, _ := cmd.Flags().GetString("ch-key")\n\tttid, _ := cmd.Flags().GetString("ttid")\n\tappVersion, _ := cmd.Flags().GetString("app-version")\n' \
        --replace-fail $'\ttalkback, _ := cmd.Flags().GetBool("talkback")\n' $'\ttalkback, _ := cmd.Flags().GetBool("talkback")\n\tif signingKey == "" || sid == "" || ecode == "" || partner == "" {\n\t\treturn fmt.Errorf("signing key, SID, ecode, and partner identity are required")\n\t}\n' \
        --replace-fail $'\tclient := tuya.NewMobileSDKClient(signingKey, sid, appKey, deviceID, chKey)\n' $'\tclient := tuya.NewMobileSDKClient(signingKey, sid, appKey, deviceID, chKey)\n\tif ttid != "" {\n\t\tclient.TTID = ttid\n\t}\n\tclient.AppVersion = appVersion\n'
    '';
    vendorHash = "sha256-wHqG1QNXmodp4Q4Go6Pnwa8+SQVgXjUxeOuxpVZSUpM=";
  };
  tuyaAlertPoller = pkgs.writeTextFile {
    name = "lionelo-alert-poller";
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      import hashlib
      import hmac
      import json
      import os
      import subprocess
      import time
      import urllib.parse
      import urllib.request
      import uuid
      from pathlib import Path

      API_URL = "https://a1.tuyaeu.com/api.json"
      CAMERA_ID = "bf53751ec1f517dcc8qi3i"
      STATE_PATH = Path("/var/lib/lionelo-camera/alert-state.json")
      MQTT = "${pkgs.mosquitto}/bin/mosquitto_pub"
      SIGN_KEYS = {
          "a", "v", "lat", "lon", "lang", "deviceId", "appVersion", "ttid",
          "isH5", "h5Token", "os", "clientId", "postData", "time", "requestId",
          "et", "n4h5", "sid", "chKey", "sp",
      }

      def sign(params):
          values = {key: value for key, value in params.items() if key in SIGN_KEYS and value}
          if "postData" in values:
              digest = hashlib.md5(values["postData"].encode()).hexdigest()
              values["postData"] = digest[8:16] + digest[0:8] + digest[24:32] + digest[16:24]
          payload = "||".join(f"{key}={values[key]}" for key in sorted(values))
          return hmac.new(os.environ["TUYA_SIGNING_KEY"].encode(), payload.encode(), hashlib.sha256).hexdigest()

      def call(action, version, data):
          params = {
              "a": action,
              "v": version,
              "time": str(int(time.time())),
              "appVersion": "1.0.3",
              "appRnVersion": "5.92",
              "channel": "oem",
              "chKey": "84d036df",
              "clientId": "qsq7hpxhsnn39jn5krpd",
              "cp": "gzip",
              "deviceCoreVersion": "6.7.0",
              "deviceId": "2e480dd6172103d1",
              "et": "0.0.1",
              "nd": "1",
              "lang": "en_US",
              "os": "Android",
              "osSystem": "14",
              "platform": "tuya_bridge",
              "requestId": str(uuid.uuid4()),
              "sdkVersion": "6.7.0",
              "sid": os.environ["TUYA_SID"],
              "timeZoneId": "Europe/Warsaw",
              "ttid": "lionelosmart",
              "postData": json.dumps(data, separators=(",", ":")),
          }
          params["sign"] = sign(params)
          request = urllib.request.Request(
              API_URL,
              urllib.parse.urlencode(params).encode(),
              {"User-Agent": "Thing-UA=APP/Android/1.0.3/SDK/6.7.0"},
          )
          with urllib.request.urlopen(request, timeout=15) as response:
              result = json.load(response)
          if not result.get("success"):
              raise RuntimeError(f"Tuya API error {result.get('errorCode')}: {result.get('errorMsg')}")
          return result.get("result")

      def publish(topic, payload, retain=False):
          command = [MQTT, "-h", "127.0.0.1", "-t", topic, "-m", payload]
          if retain:
              command.append("-r")
          subprocess.run(command, check=True)

      def publish_discovery():
          config = {
              "name": "Babyline onboard motion",
              "unique_id": "babyline_onboard_motion",
              "object_id": "babyline_onboard_motion",
              "state_topic": "lionelo/babyline/motion/state",
              "json_attributes_topic": "lionelo/babyline/motion/attributes",
              "payload_on": "ON",
              "payload_off": "OFF",
              "device_class": "motion",
              "off_delay": 30,
              "icon": "mdi:motion-sensor",
              "device": {
                  "identifiers": ["lionelo_babyline_smart"],
                  "name": "Lionelo Babyline Smart",
                  "manufacturer": "Lionelo",
                  "model": "Babyline Smart",
              },
          }
          publish("homeassistant/binary_sensor/babyline_onboard_motion/config", json.dumps(config), True)
          publish("lionelo/babyline/motion/state", "OFF", True)

      def load_last_id():
          try:
              return int(json.loads(STATE_PATH.read_text())["last_id"])
          except (FileNotFoundError, KeyError, ValueError, json.JSONDecodeError):
              return None

      def save_last_id(last_id):
          temporary = STATE_PATH.with_suffix(".tmp")
          temporary.write_text(json.dumps({"last_id": str(last_id)}))
          temporary.replace(STATE_PATH)

      def query_events():
          now = int(time.time())
          query = {
              "msgSrcId": CAMERA_ID,
              "startTime": now - 600,
              "endTime": now,
              "msgType": 4,
              "offset": 0,
              "limit": 30,
              "keepOrig": True,
          }
          return call("thing.m.msg.list.by.json", "2.0", {"json": json.dumps(query, separators=(",", ":"))}).get("datas", [])

      def event_payload(event):
          image_url = event.get("attachPics", "").split("@", 1)[0]
          return {
              "event_id": str(event.get("idStr") or event.get("id")),
              "timestamp": event.get("time"),
              "code": event.get("msgCode"),
              "title": event.get("msgTitle") or "Motion detected",
              "message": event.get("msgContent") or "Babyline Smart detected movement.",
              "image_url": image_url,
          }

      def main():
          publish_discovery()
          last_id = load_last_id()
          while True:
              try:
                  events = query_events()
                  event_ids = [int(event.get("idStr") or event.get("id")) for event in events]
                  if last_id is None:
                      last_id = max(event_ids, default=0)
                      save_last_id(last_id)
                      print(f"Initialized at event {last_id}", flush=True)
                  else:
                      for event in sorted(events, key=lambda value: int(value.get("idStr") or value.get("id"))):
                          event_id = int(event.get("idStr") or event.get("id"))
                          if event_id <= last_id:
                              continue
                          payload = event_payload(event)
                          encoded = json.dumps(payload, separators=(",", ":"))
                          publish("lionelo/babyline/motion/attributes", encoded, True)
                          publish("lionelo/babyline/events", encoded)
                          publish("lionelo/babyline/motion/state", "ON")
                          last_id = event_id
                          save_last_id(last_id)
                          print(f"Published event {event_id}", flush=True)
              except Exception as error:
                  print(f"Alert polling failed: {error}", flush=True)
              time.sleep(5)

      main()
    '';
  };
in
{
  users.groups.lionelo-camera = { };
  users.users.lionelo-camera = {
    isSystemUser = true;
    group = "lionelo-camera";
  };

  sops.secrets.lionelo_tuya_env = {
    sopsFile = ../../secrets/lionelo.yaml;
    owner = "lionelo-camera";
    group = "lionelo-camera";
    mode = "0400";
    restartUnits = [
      "lionelo-camera.service"
      "lionelo-camera-alerts.service"
    ];
  };

  systemd.services.lionelo-camera = {
    description = "Lionelo Babyline WebRTC to RTSP bridge";
    wantedBy = [ "multi-user.target" ];
    partOf = [ "frigate.service" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      User = "lionelo-camera";
      Group = "lionelo-camera";
      EnvironmentFile = config.sops.secrets.lionelo_tuya_env.path;
      StateDirectory = "lionelo-camera";
      WorkingDirectory = "/var/lib/lionelo-camera";
      ExecStart = ''
        ${aventproxy}/bin/avent-webrtc-bridge direct \
          --app-key qsq7hpxhsnn39jn5krpd \
          --device-id 2e480dd6172103d1 \
          --ch-key 84d036df \
          --ttid lionelosmart \
          --app-version 1.0.3 \
          --api-host a1.tuyaeu.com \
          --package lionelo.smart \
          --camera-id bf53751ec1f517dcc8qi3i \
          --camera-name Babyline_SMART \
          --port 38554
      '';
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/lionelo-camera" ];
    };
  };

  systemd.services.lionelo-camera-alerts = {
    description = "Lionelo Babyline onboard alert poller";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "mosquitto.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "mosquitto.service" ];
    serviceConfig = {
      User = "lionelo-camera";
      Group = "lionelo-camera";
      EnvironmentFile = config.sops.secrets.lionelo_tuya_env.path;
      StateDirectory = "lionelo-camera";
      WorkingDirectory = "/var/lib/lionelo-camera";
      ExecStart = tuyaAlertPoller;
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/lionelo-camera" ];
    };
  };
}
