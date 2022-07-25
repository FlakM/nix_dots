
{ config, pkgs, pkgsUnstable, libs, ... }:
{

  home.packages = with pkgs; [
    gnupg
    yubikey-personalization
    pinentry
  ];


}
