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

  slack-wayland = pkgs.symlinkJoin {
    name = "slack-wayland";
    paths = [ pkgs.slack ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/slack \
        --set ELECTRON_OZONE_PLATFORM_HINT wayland \
        --set NIXOS_OZONE_WL 1 \
        --set OZONE_PLATFORM_HINT wayland \
        --set OZONE_PLATFORM wayland \
        --set XDG_SESSION_TYPE wayland \
        --set XDG_CURRENT_DESKTOP Hyprland \
        --set GDK_BACKEND wayland \
        --set QT_QPA_PLATFORM wayland \
        --set QT_WAYLAND_DISABLE_WINDOWDECORATION 0 \
        --set GTK_USE_PORTAL 1 \
        --add-flags "--ozone-platform=wayland" \
        --add-flags "--enable-features=UseOzonePlatform,WaylandWindowDecorations,VaapiVideoDecoder,WebRTCPipeWireCapturer"
    '';
  };
in
{

  home.packages = with pkgs; [
    mumble
    google-chrome
    #element-desktop
    discord
    signal-desktop
    slack-wayland
    zulip-term
    #zulip
  ];

}
