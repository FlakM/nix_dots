{ pkgs, lib, ... }: {

  home.packages = with pkgs; [
    master.xwaylandvideobridge
    xorg.xwininfo

    master.slack
    google-cloud-sdk
    openfortivpn
    minio-client
    redis

  ];


}
