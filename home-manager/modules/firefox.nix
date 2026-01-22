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
    profiles.default = {
      id = 0;
      name = "Default";
      isDefault = true;

      settings = {
        # Hardware video acceleration (AMD VA-API)
        "media.ffmpeg.vaapi.enabled" = true;
        "media.av1.enabled" = true;
        "media.rdd-ffmpeg.enabled" = true;
        "media.rdd-vpx.enabled" = true;
        "media.navigator.mediadatadecoder_vpx_enabled" = true;
      };

      userChrome = ''
        @import url("tabs_on_bottom.css");
      '';
    };
  };

}
