# configuration in this file only applies to exampleHost host
#
# only zfs-root.* options can be defined in this file.
#
# all others goes to `configuration.nix` under the same directory as
# this file. 
{ pkgs, ... }: {
  zfs-root = {
    boot = {
      devNodes = "/dev/disk/by-id/";
      bootDevices = [ "nvme-Samsung_SSD_970_EVO_Plus_2TB_S4J4NX0W825442P" ];
      immutable.enable = false;
      removableEfi = true;
      luks.enable = false;
    };

  };


  networking = {
    hostName = "odroid";
    hostId = "96f5bb16";
  };
  time.timeZone = "Europe/Warsaw";

  boot.kernelParams = [ ];
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" "sdhci_pci" ];
  imports = [
    ./configuration.nix
  ];
}
