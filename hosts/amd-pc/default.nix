# configuration in this file only applies to amd-pc host
#
# only zfs-root.* options can be defined in this file.
#
# all others goes to `configuration.nix` under the same directory as
# this file. 
{ system, pkgs, ... }: {
  inherit pkgs system;
  zfs-root = {
    boot = {
      devNodes = "/dev/disk/by-id/";
      bootDevices = [

        "nvme-Samsung_SSD_990_PRO_2TB_S6Z2NJ0TB26329Y"
        "nvme-Samsung_SSD_990_PRO_2TB_S6Z2NJ0TB26332W"
      ];
      immutable = false;
      availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" "sdhci_pci" ];
      removableEfi = true;
      kernelParams = [ ];
      sshUnlock = {
        # read sshUnlock.txt file.
        enable = false;
        authorizedKeys = [ ];
      };
    };
    networking = {
      hostName = "amd-pc";
      timeZone = "Europe/Warsaw";
      hostId = "c5c1b353";
    };
  };
}
