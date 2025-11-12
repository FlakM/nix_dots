{ config, lib, pkgs, ... }: {
  imports = [
    ./boot
    ./fileSystems
    ./nix-settings.nix
    ./users/flakm.nix
  ];
}
