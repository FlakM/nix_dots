{ config, pkgs, pkgsUnstable, libs, ... }:
{
  programs.firefox = {
    enable = true;
    package = pkgs.firefox-wayland;
    profiles.default = {
      id = 0;
      name = "Default";
      isDefault = true;

      extensions = with config.nur.repos.rycee.firefox-addons; [
        ublock-origin
        darkreader
        bitwarden
      ];

      settings = {
        "layout.css.devPixelsPerPx" = "1.5";
        "widget.content.allow-gtk-dark-theme" = true;
        "widget.content.gtk-theme-override" = "Adwaita:light";
      };

      userChrome = ''
        @import url("tabs_on_bottom.css");
      '';
    };
  };
}
