{ config, pkgs, inputs, ... }: {

  # define session variables

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = 1; # Firefox Wayland
    NIXOS_OZONE_WL = "1"; # hint electron apps to use wayland
  };


  home.packages = with pkgs; [
    rofi # launcher
    dunst # notifications
    playerctl # media status for waybar
    shotman # screenshot
  ];

  # https://github.com/hyprland-community/awesome-hyprland#runners-menus-and-application-launchers
  # https://github.com/Egosummiki/dotfiles/blob/master/waybar/mediaplayer.sh
  xdg.configFile."waybar/mediaplayer.sh" = {
    source = ./mediaplayer.sh;
    executable = true;
  };

  # status bar
  programs.waybar = {
    # https://github.com/hyprwm/Hyprland/discussions/1729
    package = inputs.hyprland.packages.${pkgs.system}.waybar-hyprland;

    enable = true;
    systemd.enable = true;
    settings.mainBar = {
      layer = "top"; # Waybar at top layer
      position = "top"; # Waybar at the bottom of your screen
      height = 24; # Waybar height
      # width = 1366; // Waybar width
      modules-left = [ "custom/spotify" ];
      modules-center = [ "hyprland/window" ];
      modules-right = [ "pulseaudio" "network" "cpu" "memory" "battery" "tray" "clock" ];

      "hyprland/window" = {
        format = "{}";
        rewrite = {
          "(.*) — Mozilla Firefox" = "$1";
        };
        separate-outputs = true;
      };

      tray = {
        # icon-size = 21;
        spacing = 10;
      };

      clock = {
        format-alt = "{:%Y-%m-%d}";
      };

      cpu = {
        format = "{usage}% ";
      };

      memory = {
        format = "{}% ";
      };

      battery = {
        bat = "BAT0";
        states = {
          # good = 95;
          warning = 30;
          critical = 15;
        };
        format = "{capacity}% {icon}";
        # format-good = ""; // An empty format will hide the module
        # format-full = "";
        format-icons = [ "" "" "" "" "" ];
      };

      network = {
        # interface = "wlp2s0"; // (Optional) To force the use of this interface
        format-wifi = "{essid} ({signalStrength}%) ";
        format-ethernet = "{ifname} ";
        format-disconnected = "Disconnected ⚠";
      };

      pulseaudio = {
        # scroll-step = 1;
        format = "{volume}% {icon}";
        format-bluetooth = "{volume}% {icon}";
        format-muted = "";
        format-icons = {
          headphones = "";
          handsfree = "";
          headset = "";
          phone = "";
          portable = "";
          car = "";
          default = [ "" "" ];
        };
        on-click = "pavucontrol";
      };


      "custom/spotify" = {
        format = "  {}";
        max-length = 40;
        interval = 30; # Remove this if your script is endless and write in loop
        exec = "$HOME/.config/waybar/mediaplayer.sh 2> /dev/null"; # Script in resources folder
        #exec-if = "pgrep spotify";
      };
    };

    style = ''
      * {
            border: none;
            border-radius: 0;
            font-family: "Ubuntu Nerd Font";
            font-size: 13px;
            min-height: 0;
        }

        window#waybar {
            background: transparent;
            color: white;
        }

        #window {
            font-weight: bold;
            font-family: "Ubuntu";
        }
        /*
        #workspaces {
            padding: 0 5px;
        }
        */

        #workspaces button {
            padding: 0 5px;
            background: transparent;
            color: white;
            border-top: 2px solid transparent;
        }

        #workspaces button.focused {
            color: #c9545d;
            border-top: 2px solid #c9545d;
        }

        #mode {
            background: #64727D;
            border-bottom: 3px solid white;
        }

        #clock, #battery, #cpu, #memory, #network, #pulseaudio, #custom-spotify, #tray, #mode {
            padding: 0 3px;
            margin: 0 2px;
        }

        #clock {
            font-weight: bold;
        }

        #battery {
        }

        #battery icon {
            color: red;
        }

        #battery.charging {
        }

        @keyframes blink {
            to {
                background-color: #ffffff;
                color: black;
            }
        }

        #battery.warning:not(.charging) {
            color: white;
            animation-name: blink;
            animation-duration: 0.5s;
            animation-timing-function: linear;
            animation-iteration-count: infinite;
            animation-direction: alternate;
        }

        #cpu {
        }

        #memory {
        }

        #network {
        }

        #network.disconnected {
            background: #f53c3c;
        }

        #pulseaudio {
        }

        #pulseaudio.muted {
        }

        #custom-spotify {
            color: rgb(102, 220, 105);
        }

        #tray {
        }
    '';
  };

  wayland.windowManager.hyprland.extraConfig = ''
    env=_JAVA_AWT_WM_NONREPARENTING,1
    env=MOZ_ENABLE_WAYLAND,1
    env=NIXOS_OZONE_WL,1

    # See https://wiki.hyprland.org/Configuring/Monitors/
    monitor=,preferred,auto,1.5

    # For all categories, see https://wiki.hyprland.org/Configuring/Variables/
    input {
        kb_layout = pl
        kb_variant =
        kb_model =
        kb_options = lv3:lalt_switch
        kb_rules =
    
        follow_mouse = 1
    
        touchpad {
            natural_scroll = no
        }
    
        sensitivity = 0 # -1.0 - 1.0, 0 means no modification.
    }
    
    general {
        # See https://wiki.hyprland.org/Configuring/Variables/ for more
        gaps_in = 5
        gaps_out = 5
        border_size = 2
        col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
        col.inactive_border = rgba(595959aa)
    
        layout = dwindle
    }
    
    decoration {
        # See https://wiki.hyprland.org/Configuring/Variables/ for more
    
        rounding = 5
        
        blur {
            enabled = true
            size = 3
            passes = 1
        }
    
        drop_shadow = yes
        shadow_range = 4
        shadow_render_power = 3
        col.shadow = rgba(1a1a1aee)
    }
    
    animations {
        enabled = yes
    
        # Some default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more
    
        bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    
        animation = windows, 1, 7, myBezier
        animation = windowsOut, 1, 7, default, popin 80%
        animation = border, 1, 10, default
        animation = borderangle, 1, 8, default
        animation = fade, 1, 7, default
        animation = workspaces, 1, 6, default
    }
    
    dwindle {
        # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
        pseudotile = yes # master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
        preserve_split = yes # you probably want this
    }
    
    master {
        # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
        new_is_master = true
    }
    
    gestures {
        # See https://wiki.hyprland.org/Configuring/Variables/ for more
        workspace_swipe = off
    }
    
    # Example per-device config
    # See https://wiki.hyprland.org/Configuring/Keywords/#executing for more
    device:epic-mouse-v1 {
        sensitivity = -0.5
    }
    
    # Example windowrule v1
    # windowrule = float, ^(kitty)$
    # Example windowrule v2
    # windowrulev2 = float,class:^(kitty)$,title:^(kitty)$
    # See https://wiki.hyprland.org/Configuring/Window-Rules/ for more
    
    exec-once=[workspace 1 silent] alacritty
    exec-once=[workspace 2 silent] firefox
    exec-once=[workspace 3 silent] obsidian
    exec-once=[workspace 4 silent] spotify
    exec-once=[workspace 10 silent] slack

    # See https://wiki.hyprland.org/Configuring/Keywords/ for more
    $mainMod = SUPER

    # Execute your favorite apps at launch
    exec-once = alacritty & firefox

    bind=SUPER_SHIFT,Q,killactive,

    bind = SUPER, F, exec, firefox
    bind = , Print, exec, grimblast copy area

    # Rofi
    bind = SUPER, D, exec, rofi -show drun
    bind = SUPER, Tab, exec, hyprwin
    bind = SUPER, N, exec, network_menu
    bind = SUPER, X, exec, powermenu
    bind = SUPER, M, exec, music
    bind = SUPER, S, exec, screenshot rofi
    bind = SUPER, T, exec, themes
    bind = SUPER, R, exec, asroot
    bind = SUPER, Print, exec, recording rofi

    # workspaces
    # binds $mainMod + [shift +] {1..10} to [move to] workspace {1..10}
    ${builtins.concatStringsSep "\n" (builtins.genList (
        x: let
          ws = let
            c = (x + 1) / 10;
          in
            builtins.toString (x + 1 - (c * 10));
        in ''
          bind = $mainMod, ${ws}, workspace, ${toString (x + 1)}
          bind = $mainMod SHIFT, ${ws}, movetoworkspace, ${toString (x + 1)}
        ''
      )
      10)}

    # ...


    bindr=SUPER,h,movefocus,l
    bindr=SUPER,l,movefocus,r
    bindr=SUPER,k,movefocus,u
    bindr=SUPER,j,movefocus,d
  '';


}
