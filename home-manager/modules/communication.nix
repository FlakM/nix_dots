{ config, pkgs, pkgsUnstable, libs, ... }:
let
  signal-wrapped = pkgs.master.signal-desktop.overrideAttrs (old: {
  preFixup = old.preFixup + ''
          gappsWrapperArgs+=(
            --add-flags "--enable-features=UseOzonePlatform"
            --add-flags "--ozone-platform=wayland"
          )
        '';
  });
in
{

  home.packages = with pkgs; [
    mumble
    unstable.teams-for-linux
    google-chrome
    element-desktop
    discord
    master.signal-desktop
  ];

}


