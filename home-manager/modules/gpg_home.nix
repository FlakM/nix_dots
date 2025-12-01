{ pkgs, ... }:
{

  home.packages = with pkgs; [
    gnupg
    yubikey-personalization
    gnupg-pkcs11-scd
    pcsclite
    gpgme
  ] ++ lib.optionals stdenv.isLinux [
    pinentry-curses
  ];



}
