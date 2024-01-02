{ config, pkgs, lib, inputs, modulesPath, ... }: {
  zfs-root = {
    boot = {
      devNodes = "/dev/disk/by-id/";
      bootDevices = [ "nvme-PC401_NVMe_SK_hynix_512GB_MS88N41431210875X" ];
      immutable.enable = false;
      removableEfi = true;
      luks.enable = true;
    };
  };
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" ];
  boot.kernelParams = [ ];
  networking.hostId = "913371ac";
  networking.hostName = "dell-xps";
  time.timeZone = "Europe/Warsaw";

  # import preconfigured profiles
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    # (modulesPath + "/profiles/hardened.nix")
    # (modulesPath + "/profiles/qemu-guest.nix")
  ];
}


