{ config, pkgs, pkgsUnstable, libs, ... }:
{


  home.packages = with pkgs; [
    gnupg
    yubikey-personalization
    pinentry
    gnupg-pkcs11-scd
    pcsclite
    gpgme
  ];


  #echo "disable-ccid" >> ~/.gnupg/scdaemon.conf
  home.file."~/.gnupg/scdaemon.conf".source = config.lib.file.mkOutOfStoreSymlink ./home-manager/modules/gpg/scdeamon.conf;
  home.file."~/.gnupg/gpg.conf".source = config.lib.file.mkOutOfStoreSymlink ./home-manager/modules/gpg/gpg.conf;

}
