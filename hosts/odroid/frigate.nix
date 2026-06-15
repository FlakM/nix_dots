{ lib, ... }:
let
  frigateMountOptions = [
    "nofail"
    "X-mount.mkdir=0750"
  ];
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

      cameras = { };
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
    serviceConfig.SupplementaryGroups = lib.mkAfter [ "video" ];
  };
}
