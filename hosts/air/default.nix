{ config, pkgs, lib, inputs, modulesPath, ... }: {

  modules = [
    ./configuration.nix
  ]
}
