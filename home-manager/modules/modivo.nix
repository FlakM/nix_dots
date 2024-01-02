{ pkgs, lib, pkgs-master, ... }: {

  home.packages = with pkgs; [
    pkgs-master.xwaylandvideobridge
    xorg.xwininfo

    pkgs-master.slack
    google-cloud-sdk
    openfortivpn
    minio-client
    redis

  ];


}
