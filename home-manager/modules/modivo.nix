{ pkgs, config, lib, pkgs-master, ... }: {

  home.packages = with pkgs; [
    xorg.xwininfo

    pkgs-master.slack
    google-cloud-sdk
    openfortivpn
    minio-client
    redis

    # database schema comparing tool
    #migra
    kubectx
  ];


  home.sessionVariables = {
    KUBECONFIG = "${config.home.homeDirectory}/.kube/config";
  };



}
