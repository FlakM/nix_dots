{ pkgs, ... }:
{
  home.packages = with pkgs; [
    master.slack
    google-cloud-sdk
    openfortivpn
    minio-client
    redis
  ];

}
