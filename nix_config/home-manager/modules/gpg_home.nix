{ pkgs, ... }:
{


  home.packages = with pkgs; [
    gnupg
    yubikey-personalization
    pinentry
    gnupg-pkcs11-scd
    pcsclite
    gpgme
  ];

}
