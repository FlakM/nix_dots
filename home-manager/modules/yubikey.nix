{ config, pkgs, pkgsUnstable, libs, ... }:
{
  home.packages = with pkgs; [
    # Tools for backing up keys
    paperkey
    pgpdump

    # Yubico's official tools
    #yubikey-manager
    yubikey-personalization
    yubico-piv-tool
  ] ++ lib.optionals stdenv.isLinux [
    parted
    cryptsetup
    #yubikey-manager-qt
    yubikey-personalization-gui
    yubioath-flutter
  ];
}

