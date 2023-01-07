{ config, pkgs, pkgsUnstable, libs, ... }:
{
  home.packages = with pkgs; [
        # Tools for backing up keys
        paperkey
        pgpdump
        parted
        cryptsetup

        # Yubico's official tools
        yubikey-manager
        yubikey-manager-qt
        yubikey-personalization
        yubikey-personalization-gui
        yubico-piv-tool
        yubioath-desktop
  ];


}

