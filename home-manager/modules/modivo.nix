{ pkgs, ... }:
{
  home.packages = with pkgs; [
    unstable.slack
    google-cloud-sdk
    openfortivpn
    minio-client
    redis
  ];

}
