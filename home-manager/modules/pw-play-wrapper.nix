{ config, pkgs, lib, ... }:

{
  home.packages = lib.optionals pkgs.stdenv.isLinux [ pkgs.pipewire ];

  home.file.".local/bin/pw-play" = lib.mkIf pkgs.stdenv.isLinux {
    executable = true;
    text = ''
      #!${pkgs.bash}/bin/bash
      exec ${pkgs.pipewire}/bin/pw-play --latency 5ms --volume 1.0 "$@"
    '';
  };
}
