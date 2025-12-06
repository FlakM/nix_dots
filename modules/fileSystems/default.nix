{ config, lib, ... }:

let
  cfg = config.zfs-root.fileSystems;
  inherit (lib) mkIf types mkDefault mkOption mkMerge mapAttrsToList;
in
{
  options.zfs-root.fileSystems = {
    generateDataMounts = mkOption {
      description = "Generate fileSystems entries for ZFS datasets and bind mounts. Disable when relying on zfs-mount.service and dataset mountpoint properties instead of fstab mounts.";
      type = types.bool;
      default = true;
    };
    datasets = mkOption {
      description = "Set mountpoint for datasets";
      type = types.attrsOf types.str;
      default = { };
    };
    bindmounts = mkOption {
      description = "Set mountpoint for bindmounts";
      type = types.attrsOf types.str;
      default = { };
    };
    efiSystemPartitions = mkOption {
      description = "Set mountpoint for efi system partitions";
      type = types.listOf types.str;
      default = [ ];
    };
    swapPartitions = mkOption {
      description = "Set swap partitions";
      type = types.listOf types.str;
      default = [ ];
    };
  };
  config =
    let
      datasetMounts = mapAttrsToList
        (dataset: mountpoint: {
          "${mountpoint}" = {
            device = "${dataset}";
            fsType = "zfs";
            options = [ "X-mount.mkdir" "noatime" ];
            neededForBoot = true;
          };
        })
        cfg.datasets;

      bindMounts = mapAttrsToList
        (bindsrc: mountpoint: {
          "${mountpoint}" = {
            device = "${bindsrc}";
            fsType = "none";
            options = [ "bind" "X-mount.mkdir" "noatime" ];
          };
        })
        cfg.bindmounts;

      efiMounts = map
        (esp: {
          "/boot/efis/${esp}" = {
            device = "${config.zfs-root.boot.devNodes}${esp}";
            fsType = "vfat";
            options = [
              "nofail"
              "noatime"
              "X-mount.mkdir"
            ];
          };
        })
        cfg.efiSystemPartitions;
    in
    {
      fileSystems = mkMerge (
        (if cfg.generateDataMounts then datasetMounts ++ bindMounts else [ ])
        ++ efiMounts);

      swapDevices = mkDefault (map
        (swap: {
          device = "${config.zfs-root.boot.devNodes}${swap}";
          discardPolicy = mkDefault "both";
          randomEncryption = {
            enable = true;
            allowDiscards = mkDefault true;
          };
        })
        cfg.swapPartitions);
    };
}
