{ config
, lib
, pkgs
, ...
}:
let
  frigateMountOptions = [
    "nofail"
    "X-mount.mkdir=0750"
  ];
  reolinkCamera = address: passwordVariable: detectResolution: {
    detect = detectResolution;
    ffmpeg.inputs = [
      {
        path = "rtsp://admin:{${passwordVariable}}@${address}:554/Preview_01_main";
        input_args = "preset-rtsp-generic";
        roles = [ "record" ];
      }
      {
        path = "rtsp://admin:{${passwordVariable}}@${address}:554/Preview_01_sub";
        input_args = "preset-rtsp-generic";
        roles = [ "detect" ];
      }
    ];
  };
  reolinkMainStream = address: passwordVariable:
    "rtsp://admin:{${passwordVariable}}@${address}:554/Preview_01_main";
  go2rtcStream = address: passwordVariable: stream:
    "rtsp://admin:\${${passwordVariable}}@${address}:554/Preview_01_${stream}";
  go2rtcSettings = {
    api.listen = "127.0.0.1:1984";
    rtsp.listen = "127.0.0.1:8554";
    webrtc.listen = "127.0.0.1:8555";
    streams = {
      front_right = go2rtcStream "192.168.0.215" "FRIGATE_REOLINK_PASSWORD" "main";
      front_left = go2rtcStream "192.168.0.221" "FRIGATE_REOLINK_PASSWORD_FRONT_LEFT" "main";
      back = go2rtcStream "192.168.0.131" "FRIGATE_REOLINK_PASSWORD_BACK" "main";
    };
  };
  openvinoModel = pkgs.runCommand "frigate-openvino-model" { } ''
    mkdir -p $out
    ln -s ${pkgs.fetchurl {
      url = "https://blobconverter.nyc3.cdn.digitaloceanspaces.com/intel/2022_1/ssdlite_mobilenet_v2/ssdlite_mobilenet_v2.xml";
      hash = "sha256-sYOc199OeOId6oTftLqq2w6/MPmVM7uOeSiiErbD+yE=";
    }} $out/ssdlite_mobilenet_v2.xml
    ln -s ${pkgs.fetchurl {
      url = "https://blobconverter.nyc3.cdn.digitaloceanspaces.com/intel/2022_1/ssdlite_mobilenet_v2/ssdlite_mobilenet_v2.bin";
      hash = "sha256-CxnX7w9vjbixow2gCWdHOzw15eBdWBCrgwcVj0N5ddI=";
    }} $out/ssdlite_mobilenet_v2.bin
    ln -s ${config.services.frigate.package}/share/frigate/coco_91cl_bkgr.txt $out/coco_91cl_bkgr.txt
  '';
  frigateStart = pkgs.writeShellScript "frigate-start" ''
    export FRIGATE_REOLINK_PASSWORD="$(<${config.sops.secrets.frigate_reolink_password.path})"
    export FRIGATE_REOLINK_PASSWORD_BACK="$(<${config.sops.secrets.frigate_reolink_password_back.path})"
    export FRIGATE_REOLINK_PASSWORD_FRONT_LEFT="$(<${config.sops.secrets.frigate_reolink_password_front_left.path})"
    exec ${config.services.frigate.package.python.interpreter} -m frigate
  '';
  frigateClearShm = pkgs.writeShellScript "frigate-clear-shm" ''
    ${lib.getExe' pkgs.coreutils "rm"} -f /dev/shm/{back,front_left,front_right,reolink}_frame*
  '';
  go2rtcStart = pkgs.writeShellScript "go2rtc-start" ''
    urlencode() {
      ${config.services.frigate.package.python.interpreter} -c '
    import sys
    from urllib.parse import quote
    print(quote(sys.stdin.read().rstrip("\n"), safe=""), end="")
    '
    }
    export FRIGATE_REOLINK_PASSWORD="$(urlencode < ${config.sops.secrets.frigate_reolink_password.path})"
    export FRIGATE_REOLINK_PASSWORD_BACK="$(urlencode < ${config.sops.secrets.frigate_reolink_password_back.path})"
    export FRIGATE_REOLINK_PASSWORD_FRONT_LEFT="$(urlencode < ${config.sops.secrets.frigate_reolink_password_front_left.path})"
    exec ${lib.getExe config.services.go2rtc.package} -config ${(pkgs.formats.yaml { }).generate "go2rtc.yaml" go2rtcSettings}
  '';
in
{
  # One-time setup on odroid:
  # sudo zfs create -p -o mountpoint=legacy tank/data/frigate/recordings
  # sudo zfs create -p -o mountpoint=legacy tank/data/frigate/clips
  # sudo zfs create -p -o mountpoint=legacy tank/data/frigate/exports
  fileSystems."/var/lib/frigate/recordings" = {
    device = "tank/data/frigate/recordings";
    fsType = "zfs";
    options = frigateMountOptions;
  };

  fileSystems."/var/lib/frigate/clips" = {
    device = "tank/data/frigate/clips";
    fsType = "zfs";
    options = frigateMountOptions;
  };

  fileSystems."/var/lib/frigate/exports" = {
    device = "tank/data/frigate/exports";
    fsType = "zfs";
    options = frigateMountOptions;
  };

  sops.secrets =
    let
      frigateSecret = {
        sopsFile = ../../secrets/frigate.yaml;
        owner = "frigate";
        group = "frigate";
        mode = "0440";
        restartUnits = [ "frigate.service" ];
      };
    in
    {
      frigate_reolink_password = frigateSecret;
      frigate_reolink_password_back = frigateSecret // {
        key = "frigate_reolink_passoword_back";
      };
      frigate_reolink_password_front_left = frigateSecret // {
        key = "frigate_reolink_passoword_front_left";
      };
    };

  users.users.flakm.extraGroups = lib.mkAfter [ "frigate" ];

  services.frigate = {
    enable = true;
    hostname = "frigate.house.flakm.com";
    preCheckConfig = ''
      export FRIGATE_REOLINK_PASSWORD=validation-only
      export FRIGATE_REOLINK_PASSWORD_BACK=validation-only
      export FRIGATE_REOLINK_PASSWORD_FRONT_LEFT=validation-only
    '';
    vaapiDriver = "iHD";

    settings = {
      mqtt = {
        enabled = true;
        host = "127.0.0.1";
        topic_prefix = "frigate";
      };

      detectors.openvino = {
        type = "openvino";
        device = "GPU";
      };

      model = {
        width = 300;
        height = 300;
        input_tensor = "nhwc";
        input_pixel_format = "bgr";
        path = "${openvinoModel}/ssdlite_mobilenet_v2.xml";
        labelmap_path = "${openvinoModel}/coco_91cl_bkgr.txt";
      };

      ffmpeg.hwaccel_args = "preset-vaapi";

      detect = {
        enabled = true;
        fps = 2;
      };
      birdseye.enabled = false;
      objects = {
        track = [ "person" ];
        filters.person = {
          min_score = 0.6;
          threshold = 0.8;
        };
      };

      go2rtc.streams = {
        front_right = reolinkMainStream "192.168.0.215" "FRIGATE_REOLINK_PASSWORD";
        front_left = reolinkMainStream "192.168.0.221" "FRIGATE_REOLINK_PASSWORD_FRONT_LEFT";
        back = reolinkMainStream "192.168.0.131" "FRIGATE_REOLINK_PASSWORD_BACK";
      };

      record = {
        enabled = true;
        retain = {
          days = 7;
          mode = "all";
        };
        alerts.retain = {
          days = 90;
          mode = "motion";
        };
        detections.retain = {
          days = 90;
          mode = "motion";
        };
      };

      snapshots = {
        enabled = true;
        clean_copy = true;
        timestamp = true;
        bounding_box = true;
        retain.default = 90;
      };

      cameras = {
        front_right = (reolinkCamera "192.168.0.215" "FRIGATE_REOLINK_PASSWORD" {
          width = 640;
          height = 360;
        }) // {
          motion.mask = "0.001,0.009,0.001,0.221,0.273,0.201,0.3,0.162,0.433,0.164,0.445,0.216,0.853,0.265,0.899,0.09,0.911,0.004";
          zones.podjazd_prawy = {
            friendly_name = "Podjazd prawy";
            coordinates = "0.01,0.237,0.854,0.313,0.853,0.982,0.004,0.995";
            loitering_time = 0;
          };
          review = {
            alerts.required_zones = [ "podjazd_prawy" ];
            detections.required_zones = [ "podjazd_prawy" ];
          };
        };
        front_left = (reolinkCamera "192.168.0.221" "FRIGATE_REOLINK_PASSWORD_FRONT_LEFT" {
          width = 640;
          height = 360;
        }) // {
          motion.mask = "0.002,0.008,0.007,0.397,0.353,0.264,0.577,0.19,0.793,0.169,0.897,0.152,0.991,0.119,0.985,0.01";
          zones.podjazd = {
            coordinates = "0.156,0.358,0.005,0.427,0.001,0.993,0.996,0.995,0.999,0.176,0.887,0.208,0.843,0.196";
            loitering_time = 0;
          };
          review = {
            alerts.required_zones = [ "podjazd" ];
            detections.required_zones = [ "podjazd" ];
          };
        };
        back = (reolinkCamera "192.168.0.131" "FRIGATE_REOLINK_PASSWORD_BACK" {
          width = 1280;
          height = 384;
        }) // {
          objects.filters.person = {
            min_area = 0.005;
            min_score = 0.65;
            threshold = 0.85;
          };
          motion.mask = [
            "0,0.365,0,0.009,0.269,0.004"
            "0.659,0.004,0.99,0.5,0.998,0.469,0.997,0.004"
          ];
          zones.ogrod = {
            friendly_name = "Ogród";
            coordinates = "0,0.365,0.269,0.004,0.659,0.004,0.99,0.5,1,1,0,1";
            objects = [ "person" ];
            loitering_time = 0;
          };
          review = {
            alerts.required_zones = [ "ogrod" ];
            detections.required_zones = [ "ogrod" ];
          };
        };
      };
    };
  };

  services.nginx.virtualHosts."frigate.house.flakm.com" = {
    useACMEHost = "house.flakm.com";
    forceSSL = true;
  };

  services.go2rtc = {
    enable = true;
    settings = go2rtcSettings;
  };

  systemd.services.go2rtc.serviceConfig = {
    ExecStart = lib.mkForce go2rtcStart;
    SupplementaryGroups = lib.mkAfter [ "frigate" ];
  };

  systemd.services.frigate = {
    unitConfig.RequiresMountsFor = [
      "/var/lib/frigate/recordings"
      "/var/lib/frigate/clips"
      "/var/lib/frigate/exports"
    ];
    serviceConfig = {
      ExecStart = lib.mkForce frigateStart;
      ExecStartPre = lib.mkBefore [
        "+${frigateClearShm}"
        "+${lib.getExe' pkgs.coreutils "install"} -d -m 0750 -o frigate -g frigate /var/lib/frigate/recordings /var/lib/frigate/clips /var/lib/frigate/exports"
      ];
      SupplementaryGroups = lib.mkAfter [ "video" ];
    };
  };
}
