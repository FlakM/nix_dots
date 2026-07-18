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

  google-chrome-wayland = pkgs.symlinkJoin {
    name = "google-chrome-wayland";
    paths = [ pkgs.google-chrome ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/google-chrome-stable \
        --set NIXOS_OZONE_WL 1 \
        --add-flags "--ozone-platform=wayland" \
        --add-flags "--enable-features=UseOzonePlatform,VaapiVideoEncoder" \
        --add-flags "--disable-features=VaapiVideoDecoder,VaapiAV1Decoder"

      # Replace symlinked .desktop file so launcher-spawned Chrome goes
      # through the wrapper too (otherwise the .desktop Exec= points
      # straight at the underlying binary, bypassing all wrapper flags).
      rm $out/share/applications/google-chrome.desktop
      cp ${pkgs.google-chrome}/share/applications/google-chrome.desktop \
         $out/share/applications/google-chrome.desktop
      chmod +w $out/share/applications/google-chrome.desktop
      substituteInPlace $out/share/applications/google-chrome.desktop \
        --replace ${pkgs.google-chrome}/bin/google-chrome-stable \
                  $out/bin/google-chrome-stable
    '';
  };

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

  zulip-wayland = pkgs.symlinkJoin {
    name = "zulip-wayland";
    paths = [ pkgs.zulip ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/zulip \
        --set ELECTRON_OZONE_PLATFORM_HINT wayland \
        --set NIXOS_OZONE_WL 1 \
        --add-flags "--ozone-platform=wayland" \
        --add-flags "--enable-features=UseOzonePlatform,WaylandWindowDecorations,WebRTCPipeWireCapturer"
    '';
  };
in
{

  home.packages = with pkgs; [
    mumble
    google-chrome-wayland
    #element-desktop
    discord
    pkgs-master.signal-cli
    signal-desktop
    slack-wayland
    zulip-term
    zulip-wayland
  ];

}
