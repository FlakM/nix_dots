{ config, pkgs, lib, ... }:

{
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.pipewire ];

  home.file.".local/bin/pw-play" = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    executable = true;
    text = ''
      #!${pkgs.bash}/bin/bash
      exec ${pkgs.pipewire}/bin/pw-play --volume 1.0 "$@"
    '';
  };
}
