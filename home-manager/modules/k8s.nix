{ pkgs, config, lib, pkgs-master, ... }: {

  home.packages = with pkgs; [
    teleport


    kubectx
  ];
}
