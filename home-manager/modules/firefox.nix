{ config, pkgs, pkgsUnstable, libs, ... }:
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
        # Hardware video acceleration (AMD VA-API)
        "media.ffmpeg.vaapi.enabled" = true;
        # AV1 hardware decode on Raphael (VCN3) + Mesa produces green frames on
        # YouTube; force VP9 fallback until upstream fixes it.
        "media.av1.enabled" = false;
        "media.rdd-ffmpeg.enabled" = true;
        "media.rdd-vpx.enabled" = true;
        "media.navigator.mediadatadecoder_vpx_enabled" = true;
        # Hyprland 0.55 xdg-popup interactions break context menus.
        # move-to-rect=false fixed the empty-popup variant; fractional-scale
        # disable handles the no-popup-at-all variant where right-click
        # produces nothing on the screen.
        "widget.wayland.use-move-to-rect" = false;
        "widget.wayland.fractional-scale.enabled" = false;
      };

      userChrome = ''
        @import url("tabs_on_bottom.css");
      '';
    };
  };

}
