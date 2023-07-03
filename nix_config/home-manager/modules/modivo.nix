{ pkgs, ... }:
{

  home.packages = with pkgs; [
    slack

    google-cloud-sdk

    unstable.openfortivpn
  ];

}
