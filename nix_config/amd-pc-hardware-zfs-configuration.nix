{ config, pkgs, ... }:

{ boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "c5c1b353";
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
boot.loader.efi.efiSysMountPoint = "/boot/efi";
boot.loader.efi.canTouchEfiVariables = false;
boot.loader.generationsDir.copyKernels = true;
boot.loader.grub.efiInstallAsRemovable = true;
boot.loader.grub.enable = true;
boot.loader.grub.copyKernels = true;
boot.loader.grub.efiSupport = true;
boot.loader.grub.zfsSupport = true;
boot.loader.grub.extraPrepareConfig = ''
  mkdir -p /boot/efis
  for i in  /boot/efis/*; do mount $i ; done

  mkdir -p /boot/efi
  mount /boot/efi
'';
boot.loader.grub.extraInstallCommands = ''
ESP_MIRROR=$(mktemp -d)
cp -r /boot/efi/EFI $ESP_MIRROR
for i in /boot/efis/*; do
 cp -r $ESP_MIRROR/EFI $i
done
rm -rf $ESP_MIRROR
'';
boot.loader.grub.devices = [
      "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S6Z2NJ0TB26329Y"
      "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S6Z2NJ0TB26332W"
    ];
users.users.root.initialHashedPassword = "$6$tHA8.wENA9olzcU7$f6hHz49MSmYupwXeuBYUN8MGNYcIO4GX19aVkK2wet.moGG8t1AZk3VA.FjvS60AUU.KoclZR1xeG.HiOU5dF0";
}

