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
    pkgs-unstable.teams-for-linux
    (google-chrome.override {
      commandLineArgs = [
        "--enable-features=UseOzonePlatform"
        "--ozone-platform=wayland"
      ];
    })
    element-desktop
    discord
    pkgs-master.signal-desktop
    zulip-term
    zulip
  ];

}


