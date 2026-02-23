# configuration in this file only applies to amd-pc host
#
# only zfs-root.* options can be defined in this file.
#
# all others goes to `configuration.nix` under the same directory as
# this file. 
#{ ... }: {
#  zfs-root = {
#    boot = {
#      devNodes = "/dev/disk/by-id/";
#      bootDevices = [
#
#        "nvme-Samsung_SSD_990_PRO_2TB_S6Z2NJ0TB26329Y"
#        "nvme-Samsung_SSD_990_PRO_2TB_S6Z2NJ0TB26332W"
#      ];
#      immutable.enable = false;
#      availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" "sdhci_pci" ];
#      removableEfi = true;
#      kernelParams = [ ];
#      sshUnlock = {
#        # read sshUnlock.txt file.
#        enable = false;
#        authorizedKeys = [ ];
#      };
#    };
#    networking = {
#      hostName = "amd-pc";
#      timeZone = "Europe/Warsaw";
#      hostId = "c5c1b353";
#    };
#  };
#}



{ config, pkgs, lib, inputs, modulesPath, ... }: {
  zfs-root = {
    boot = {
      devNodes = "/dev/disk/by-id/";
      bootDevices = [
        "nvme-Samsung_SSD_990_PRO_2TB_S6Z2NJ0TB26329Y"
        "nvme-Samsung_SSD_990_PRO_2TB_S6Z2NJ0TB26332W"
      ];
      immutable.enable = false;
      removableEfi = true;
      luks.enable = false;
    };
    fileSystems.generateDataMounts = false;
  };

  # System boots via UEFI; skip legacy BIOS grub install to avoid failures.
  boot.loader.grub.devices = lib.mkForce [ "nodev" ];
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" "sdhci_pci" ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.kernelParams = [
    "amd_pstate=guided"
    "amd_iommu=on"
    "iommu=pt"
  ];

  # AMD CPU microcode updates
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  networking.hostId = "c5c1b353";
  networking.hostName = "amd-pc";
  time.timeZone = "Europe/Warsaw";
  imports = [
    (modulesPath + "/installer/scan/detected.nix")
    ./configuration.nix
  ];
}
