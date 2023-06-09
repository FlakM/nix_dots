{ config, pkgs, libs, ... }:
{

  wayland.windowManager.sway = {
    enable = true;
    systemdIntegration = true;
    #wrapperFeatures.gtk = true;

    config = {
      modifier = "Mod4";
      #menu = "wofi --show run";
      #bars = [
      #  {
      #    fonts.size = 15.0;
      #    position = "bottom";
      #    command = "waybar";
      #  }
      #];

      terminal = "alacritty";
      startup = [
        # Launch Firefox on start
        { command = "alacritty"; }
      ];
    };
  };
}
