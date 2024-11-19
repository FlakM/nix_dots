{ pkgs, inputs, lib, pkgs-unstable, pkgs-master, config, ... }:
{




  system.stateVersion = 1;


  environment.systemPackages = with pkgs; [
    bat
  ];

}

