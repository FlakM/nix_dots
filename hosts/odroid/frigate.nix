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
  frigateStart = pkgs.writeShellScript "frigate-start" ''
    export FRIGATE_REOLINK_PASSWORD="$(${config.services.frigate.package.python.interpreter} -c '
    import sys
    from urllib.parse import quote
    print(quote(sys.stdin.read().rstrip("\n"), safe=""), end="")
    ' < ${config.sops.secrets.frigate_reolink_password.path})"
    exec ${config.services.frigate.package.python.interpreter} -m frigate
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

  sops.secrets.frigate_reolink_password = {
    sopsFile = ../../secrets/frigate.yaml;
    owner = "frigate";
    group = "frigate";
    mode = "0400";
    restartUnits = [ "frigate.service" ];
  };

  services.frigate = {
    enable = true;
    hostname = "frigate.house.flakm.com";
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

      cameras.reolink = {
        ffmpeg.inputs = [
          {
            path = "rtsp://admin:{FRIGATE_REOLINK_PASSWORD}@192.168.0.215:554/Preview_01_main";
            input_args = "preset-rtsp-generic";
            roles = [ "record" ];
          }
          {
            path = "rtsp://admin:{FRIGATE_REOLINK_PASSWORD}@192.168.0.215:554/Preview_01_sub";
            input_args = "preset-rtsp-generic";
            roles = [ "detect" ];
          }
        ];
      };
    };
  };

  services.nginx.virtualHosts."frigate.house.flakm.com" = {
    useACMEHost = "house.flakm.com";
    forceSSL = true;
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
        "+${lib.getExe' pkgs.coreutils "install"} -d -m 0750 -o frigate -g frigate /var/lib/frigate/recordings /var/lib/frigate/clips /var/lib/frigate/exports"
      ];
      SupplementaryGroups = lib.mkAfter [ "video" ];
    };
  };
}
