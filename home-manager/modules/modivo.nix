{ pkgs, ... }:
{
  home.packages = with pkgs; [
    slack
    google-cloud-sdk
    openfortivpn
    minio-client
    redis
  ];

}
