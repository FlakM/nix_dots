{ config, lib, osConfig, pkgs, pkgsUnstable, libs, ... }:
let
  isAmdPc = lib.attrByPath [ "networking" "hostName" ] "" osConfig == "amd-pc";
in
{

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "firefox.desktop";
      "default-web-browser" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "default-url-scheme-handler" = "firefox.desktop";
      "scheme-handler/http" = "firefox.desktop";
      "scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
      "x-scheme-handler/mailto" = "thunderbird.desktop";
      "default-url-scheme-handler/http" = "firefox.desktop";
      "default-url-scheme-handler/https" = "firefox.desktop";
    };
  };

  programs.firefox = {
    enable = true;
    # 26.05 moves the default to ~/.config; keep the legacy path (existing profile).
    configPath = ".mozilla/firefox";
    profiles.default = {
      id = 0;
      name = "Default";
      isDefault = true;
      settings = {
        # Broken Wayland HDR path produced green video artifacts.
        "gfx.wayland.hdr" = false;
      }
      // lib.optionalAttrs isAmdPc {
        # VCN corrupts H.264/AV1 hw decode (green frames); decode in software.
        "media.hardware-video-decoding.enabled" = false;
        "media.ffmpeg.vaapi.enabled" = false;
      };
    };
  };

}
