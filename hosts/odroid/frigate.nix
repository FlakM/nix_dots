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
  reolinkCamera = address: passwordVariable: {
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
      reolink = go2rtcStream "192.168.0.215" "FRIGATE_REOLINK_PASSWORD" "main";
      front_left = go2rtcStream "192.168.0.221" "FRIGATE_REOLINK_PASSWORD_FRONT_LEFT" "main";
      back = go2rtcStream "192.168.0.131" "FRIGATE_REOLINK_PASSWORD_BACK" "main";
    };
  };
  frigateStart = pkgs.writeShellScript "frigate-start" ''
    export FRIGATE_REOLINK_PASSWORD="$(<${config.sops.secrets.frigate_reolink_password.path})"
    export FRIGATE_REOLINK_PASSWORD_BACK="$(<${config.sops.secrets.frigate_reolink_password_back.path})"
    export FRIGATE_REOLINK_PASSWORD_FRONT_LEFT="$(<${config.sops.secrets.frigate_reolink_password_front_left.path})"
    exec ${config.services.frigate.package.python.interpreter} -m frigate
  '';
  frigateClearShm = pkgs.writeShellScript "frigate-clear-shm" ''
    ${lib.getExe' pkgs.coreutils "rm"} -f /dev/shm/{back,front_left,reolink}_frame*
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

      detectors.cpu = {
        type = "cpu";
      };

      ffmpeg.hwaccel_args = "preset-vaapi";

      go2rtc.streams = {
        reolink = reolinkMainStream "192.168.0.215" "FRIGATE_REOLINK_PASSWORD";
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
        reolink = reolinkCamera "192.168.0.215" "FRIGATE_REOLINK_PASSWORD";
        front_left = reolinkCamera "192.168.0.221" "FRIGATE_REOLINK_PASSWORD_FRONT_LEFT";
        back = reolinkCamera "192.168.0.131" "FRIGATE_REOLINK_PASSWORD_BACK";
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
