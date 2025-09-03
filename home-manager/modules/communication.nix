{ config, pkgs, pkgs-unstable, pkgs-master, libs, ... }:
let
  signal-wrapped = pkgs-master.signal-desktop.overrideAttrs (old: {
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
    google-chrome
    #element-desktop
    discord
    signal-desktop
    slack
    zulip-term
    #zulip
  ];

}


