{ config, lib, pkgs, ... }:

let 
  mod = "Mod4";
in {
  home.packages = with pkgs; [
    pamixer
  ];
  
  programs.i3status-rust = {
    enable = true;
    bars.bottom = {
      theme = "gruvbox-dark";
      icons = "awesome5";
      #font = {
      #  name = "Roboto Mono Nerd Font";
      #  size =15;
      #};
    };
    #settings = { 
    #  theme =  {
    #    name = "solarized-dark";
    #    overrides = {
    #      idle_bg = "#123456";
    #      idle_fg = "#abcdef";
    #    };
    #  }; 
    #};
  };
  xsession.windowManager.i3 = {
    enable = true;
    config = {
      modifier = mod;

      #fonts = ["RobotoMono Nerd Font"];

      fonts = {
        names = [ "RobotoMono Nerd Font" ];
      };

      keybindings = lib.mkOptionDefault {
        "${mod}+p" = "exec ${pkgs.dmenu}/bin/dmenu_run";
        "${mod}+x" = "exec sh -c '${pkgs.maim}/bin/maim -s | xclip -selection clipboard -t image/png'";
        "${mod}+Shift+x" = "exec sh -c '${pkgs.i3lock}/bin/i3lock -c 222222 & sleep 5 && xset dpms force of'";

        # Focus
        "${mod}+h" = "focus left";
        "${mod}+j" = "focus down";
        "${mod}+k" = "focus up";
        "${mod}+l" = "focus right";

        # Move
        "${mod}+Shift+h" = "move left";
        "${mod}+Shift+j" = "move down";
        "${mod}+Shift+k" = "move up";
        "${mod}+Shift+l" = "move right";

        # My multi monitor setup
        "${mod}+m" = "move workspace to output DP-2";
        "${mod}+Shift+m" = "move workspace to output DP-5";
      };

      bars = [
        {
          position = "bottom";
          statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ~/.config/i3status-rust/config-bottom.toml";

          fonts = {
            names = [ "RobotoMono Nerd Font" ];
            size = 18.0;
          };
        }
      ];
    };
  };
}
