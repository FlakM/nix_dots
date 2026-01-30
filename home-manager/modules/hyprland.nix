{ config, pkgs, inputs, pkgs-unstable, lib, osConfig, ... }:
let
  path = "${config.home.homeDirectory}/.config/current-color_scheme";
  apply-theme-script = pkgs.writeScript "apply-theme" ''
    set -e
    curr=$(cat ${path})
    
    function switch_theme() {
      echo $1 > ${path}
      echo "Current theme: `cat ${path}`"
    }

    if [ ! -f ${path} ]; then
      touch ${path}
      echo "prefer-light" > ${path}
    fi


    if [ "$curr" = "prefer-light" ]; then
      switch_theme "prefer-dark"
      ~/.config/kitty/switch.sh dark ${path}
      ${configure-gtk-dark}/bin/configure-gtk-dark

      for server in $(nvr --serverlist); do
        nvr --servername "$server" -cc 'lua vim.g.background = "dark"; vim.cmd("set background=dark"); vim.cmd("colorscheme edge")'
      done
    else
      switch_theme "prefer-light"
      ~/.config/kitty/switch.sh light ${path}
      ${configure-gtk-light}/bin/configure-gtk-light

      for server in $(nvr --serverlist); do
        nvr --servername "$server" -cc 'lua vim.g.background = "light"; vim.cmd("set background=light"); vim.cmd("colorscheme edge"); vim.api.nvim_set_hl(0, "Visual", { bg = "#ffc0cb", fg = "NONE" })'
      done
    fi
  '';
  # currently, there is some friction between sway and gtk:
  # https://github.com/swaywm/sway/wiki/GTK-3-settings-on-Wayland
  # the suggested way to set gtk settings is with gsettings
  # for gsettings to work, we need to tell it where the schemas are
  # using the XDG_DATA_DIR environment variable
  # run at the end of sway config
  configure-gtk-dark = pkgs.writeTextFile {
    name = "configure-gtk-dark";
    destination = "/bin/configure-gtk-dark";
    executable = true;
    text =
      let
        schema = pkgs.gsettings-desktop-schemas;
        datadir = "${schema}/share/gsettings-schemas/${schema.name}";
      in
      ''
        export XDG_DATA_DIRS=${datadir}:$XDG_DATA_DIRS
        gnome_schema=org.gnome.desktop.interface
        gsettings set $gnome_schema gtk-theme 'Adwaita-dark'
        dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
      '';
  };


  configure-gtk-light = pkgs.writeTextFile {
    name = "configure-gtk";
    destination = "/bin/configure-gtk-light";
    executable = true;
    text =
      let
        schema = pkgs.gsettings-desktop-schemas;
        datadir = "${schema}/share/gsettings-schemas/${schema.name}";
      in
      ''
        export XDG_DATA_DIRS=${datadir}:$XDG_DATA_DIRS
        gnome_schema=org.gnome.desktop.interface
        gsettings set $gnome_schema gtk-theme 'Adwaita'
        dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
      '';
  };

in
{


  xdg = {
    portal = {
      enable = true;

      config = {
        common = {
          default = [
            "hyprland"
            "gtk"
          ];
        };
        hyprland = {
          default = [
            "hyprland"
            "gtk"
          ];
          "org.freedesktop.impl.portal.ScreenCast" = [
            "hyprland"
          ];
          "org.freedesktop.impl.portal.Screenshot" = [
            "hyprland"
          ];
        };
      };

      xdgOpenUsePortal = true;

      extraPortals = [
        inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland
        pkgs.xdg-desktop-portal-gtk
      ];
    };
  };

  # define session variables
  home.sessionVariables = {
    # https://wiki.hyprland.org/Configuring/Environment-variables/
    MOZ_ENABLE_WAYLAND = 1; # Firefox Wayland

    # Hardware video acceleration (VA-API for AMD)
    LIBVA_DRIVER_NAME = "radeonsi";
    VDPAU_DRIVER = "radeonsi";

    # PipeWire screen sharing fixes
    PIPEWIRE_LATENCY = "512/48000";
    PIPEWIRE_RT_PRIO = "20";
    PIPEWIRE_BUFFER_SIZE = "512";

    # Portal session fixes for Electron apps
    XDG_RUNTIME_DIR = "/run/user/1000";
    HYPRLAND_NO_RT = "1";
    MOZ_DBUS_REMOTE = 1; # Firefox wayland
    MOZ_USE_XINPUT2 = 1; # Firefox smooth scrolling
    MOZ_WAYLAND_USE_VAAPI = 1; # Firefox hardware acceleration
    GDK_BACKEND = "wayland";

    NIXOS_OZONE_WL = "1"; # hint electron apps to use wayland
    ELECTRON_OZONE_PLATFORM_HINT = "wayland";
    OZONE_PLATFORM_HINT = "wayland";
    OZONE_PLATFORM = "wayland";

    SDL_VIDEODRIVER = "wayland";
    _JAVA_AWT_WM_NONREPARENTING = "1";

    #NIXOS_XDG_OPEN_USE_PORTAL = "0";
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_TYPE = "wayland";
    XDG_SESSION_DESKTOP = "Hyprland";

    GTK_USE_PORTAL = "1";

    CLUTTER_BACKEND = "wayland";

    DEFAULT_BROWSER = "${pkgs.firefox}/bin/firefox";
    BROWSER = "${pkgs.firefox}/bin/firefox";

    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    QT_QPA_PLATFORM = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    QT_QPA_PLATFORMTHEME = "qt5ct";
  };


  home.packages = with pkgs; [
      swaynotificationcenter # modern notifications
      rofi
      libnotify # provides notify-send for testing
      playerctl # media status for waybar
      shotman # screenshot
      dconf
      copyq

      configure-gtk-dark
      configure-gtk-light
      wl-clipboard
      wtype # for typing clipboard content
      xclip # for compatibility

      #unstable.xdg-utils
      handlr

      hyprland-protocols
      hyprpaper # wallpaper utility

      grim
      swappy
      slurp

      pkgs-unstable.grimblast
      pkgs-unstable.walker # application launcher & clipboard UI
      brightnessctl # brightness control
      rofimoji

      wf-recorder # screen recording
    ];

  xdg.configFile."rofimoji.rc" = {
    text = ''
      selector-args = "-kb-custom-1 Control+1 -kb-custom-2 Control+2 -kb-custom-3 Control+3"
    '';
  };

  # https://github.com/hyprland-community/awesome-hyprland#runners-menus-and-application-launchers
  # https://github.com/Egosummiki/dotfiles/blob/master/waybar/mediaplayer.sh
  xdg.configFile."waybar/mediaplayer.sh" = {
    source = ./mediaplayer.sh;
    executable = true;
  };

  gtk = {
    enable = true;
  };

  xdg.configFile."theme-switch.sh" = {
    text = ''
      #!/usr/bin/env sh
      ${apply-theme-script}
    '';
    executable = true;
  };

  # hyprpaper configuration
  xdg.configFile."hypr/hyprpaper.conf" = {
    text = let
      wallpaperPath = "${config.home.homeDirectory}/.config/wallpaper.png";
    in ''
      # Preload wallpaper
      preload = ${wallpaperPath}
      
      # Set wallpaper for monitor
      wallpaper = DP-1,${wallpaperPath}
      
      # Enable splash text
      splash = false
      
      # Enable IPC for runtime control
      ipc = on
    '';
  };

  # Manage wallpaper file
  xdg.configFile."wallpaper.png" = {
    source = "${inputs.self}/wallpapers/wallpaper.png";
  };

  # SwayNotificationCenter configuration
  xdg.configFile."swaync/config.json" = {
    text = builtins.toJSON {
      positionX = "center";
      positionY = "top";
      layer = "overlay";
      control-center-layer = "top";
      layer-shell = true;
      cssPriority = "application";
      control-center-margin-top = 60;
      control-center-margin-bottom = 20;
      control-center-margin-right = 40;
      control-center-margin-left = 40;
      notification-2fa-command = true;
      notification-inline-replies = false;
      notification-icon-size = 80;
      notification-body-image-height = 120;
      notification-body-image-width = 240;
      timeout = 10;
      timeout-low = 5;
      timeout-critical = 0;
      fit-to-screen = false;
      control-center-width = 700;
      control-center-height = 800;
      notification-window-width = 800;
      notification-window-height = -1;
      keyboard-shortcuts = true;
      image-visibility = "when-available";
      transition-time = 200;
      hide-on-clear = false;
      hide-on-action = true;
      script-fail-notify = true;
    };
  };

  xdg.configFile."swaync/style.css" = {
    text = ''
      * {
        font-family: "FiraCode Nerd Font";
        font-weight: bold;
        font-size: 16px;
      }

      /* Notification window styling - AUTO SIZING */
      .notification-row {
        outline: none;
        margin: 15px;
      }

      .notification-row:focus,
      .notification-row:hover {
        background: rgba(255, 255, 255, 0.08);
        border-radius: 24px;
      }

      /* Individual notification styling - AUTO SIZING */
      .notification {
        background: rgba(16, 16, 24, 0.9);
        border: 3px solid rgba(51, 204, 255, 0.4);
        border-radius: 24px;
        margin: 15px auto;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4), 
                    0 0 0 1px rgba(255, 255, 255, 0.05);
        transition: all 0.3s ease;
        opacity: 0.95;
      }

      .notification:hover {
        background: rgba(20, 20, 32, 0.92);
        border-color: rgba(51, 204, 255, 0.6);
        box-shadow: 0 12px 40px rgba(0, 0, 0, 0.5), 
                    0 0 30px rgba(51, 204, 255, 0.15),
                    0 0 0 1px rgba(255, 255, 255, 0.08),
                    inset 0 1px 0 rgba(255, 255, 255, 0.15);
        opacity: 1.0;
      }

      /* Notification header - BIGGER TEXT */
      .notification-content .notification-header {
        margin-bottom: 12px;
      }

      .notification-content .notification-header .notification-title {
        color: #ffffff;
        font-size: 20px;
        font-weight: bold;
        text-shadow: 0 1px 2px rgba(0, 0, 0, 0.5);
      }

      .notification-content .notification-header .notification-time {
        color: rgba(255, 255, 255, 0.6);
        font-size: 14px;
        opacity: 0.8;
      }

      /* Notification body - LARGER & MORE READABLE */
      .notification-content .notification-body {
        color: rgba(255, 255, 255, 0.85);
        font-size: 16px;
        line-height: 1.5;
        margin-top: 12px;
        font-weight: normal;
      }

      /* Notification icon - MUCH BIGGER */
      .notification-icon {
        margin-right: 20px;
        min-width: 80px;
        min-height: 80px;
      }

      .notification-icon image {
        border-radius: 20px;
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
      }

      /* Close button */
      .close-button {
        background: rgba(255, 80, 80, 0.8);
        border: 2px solid rgba(255, 100, 100, 0.4);
        border-radius: 50%;
        color: white;
        transition: all 0.3s ease;
      }

      .close-button:hover {
        background: rgba(255, 60, 60, 0.9);
        border-color: rgba(255, 80, 80, 0.6);
        box-shadow: 0 4px 12px rgba(255, 60, 60, 0.3);
        opacity: 1.0;
      }

      /* Control Center */
      .control-center {
        background: rgba(12, 12, 20, 0.95);
        border: 3px solid rgba(51, 204, 255, 0.3);
        border-radius: 20px;
        margin: 16px;
        box-shadow: 0 16px 48px rgba(0, 0, 0, 0.6);
      }

      .control-center .notification-row:first-child > .notification {
        margin-top: 16px;
      }

      .control-center .notification-row:last-child > .notification {
        margin-bottom: 16px;
      }

      /* Control center header */
      .control-center-list-placeholder {
        color: rgba(255, 255, 255, 0.6);
        font-size: 18px;
        margin: 24px;
        text-align: center;
      }

      /* Urgency-specific styling - MORE DRAMATIC */
      .notification.critical {
        border-color: rgba(255, 80, 80, 0.6);
        background: rgba(32, 16, 16, 0.9);
        box-shadow: 0 8px 32px rgba(255, 80, 80, 0.2), 
                    0 0 0 1px rgba(255, 100, 100, 0.1),
                    inset 0 1px 0 rgba(255, 255, 255, 0.1);
      }

      .notification.critical:hover {
        border-color: rgba(255, 80, 80, 0.8);
        background: rgba(40, 20, 20, 0.95);
        box-shadow: 0 12px 40px rgba(255, 80, 80, 0.3),
                    0 0 30px rgba(255, 80, 80, 0.2);
      }

      .notification.low {
        border-color: rgba(150, 150, 150, 0.3);
        background: rgba(20, 20, 20, 0.8);
        opacity: 0.85;
      }

      /* Action buttons */
      .notification-action {
        background: rgba(51, 204, 255, 0.2);
        border: 2px solid rgba(51, 204, 255, 0.4);
        border-radius: 12px;
        color: white;
        font-weight: bold;
        margin: 4px;
        transition: all 0.3s ease;
      }

      .notification-action:hover {
        background: rgba(51, 204, 255, 0.3);
        border-color: rgba(51, 204, 255, 0.6);
        box-shadow: 0 4px 12px rgba(51, 204, 255, 0.2);
      }

      /* Progress bars - MORE VISIBLE */
      .notification-progress {
        background: rgba(255, 255, 255, 0.15);
        border-radius: 8px;
        margin: 12px 0;
        overflow: hidden;
        height: 8px;
      }

      .notification-progress-bar {
        background: linear-gradient(90deg, #33ccff, #00ff99);
        height: 100%;
        border-radius: 8px;
        transition: width 0.4s cubic-bezier(0.4, 0.0, 0.2, 1);
        box-shadow: 0 0 8px rgba(51, 204, 255, 0.4);
      }

      /* Additional modern effects */
      .notification-content {
        position: relative;
      }

      .notification-content::before {
        content: "";
        position: absolute;
        top: -1px;
        left: -1px;
        right: -1px;
        bottom: -1px;
        background: linear-gradient(45deg, 
                    rgba(51, 204, 255, 0.1), 
                    rgba(0, 255, 153, 0.1), 
                    rgba(51, 204, 255, 0.1));
        border-radius: 28px;
        z-index: -1;
        opacity: 0;
        transition: opacity 0.3s ease;
      }

      .notification:hover .notification-content::before {
        opacity: 1;
      }
    '';
  };

  # Walker configuration inspired by https://benz.gitbook.io/walker/ docs
  xdg.configFile."walker/config.toml" = {
    text = ''
      as_window = true
      theme = "large"

      [providers]
      default = [
        "desktopapplications",
        "clipboard",
        "calc",
        "runner",
        "menus",
        "websearch",
      ]
      empty = ["desktopapplications", "clipboard"]
      previews = [
        "clipboard",
        "files",
        "menus",
      ]
      max_results = 100

      [providers.clipboard]
      time_format = "%H:%M"

      [builtins.clipboard]
      switcher_only = false
      max_entries = 30
      always_put_new_on_top = true
    '';
  };

  xdg.configFile."walker/themes/large.toml" = {
    text = ''
      [ui.anchors]
      bottom = false
      left = false
      right = false
      top = false

      [ui.window]
      h_align = "fill"
      v_align = "fill"
      height = 840
      width = 1120
      max_width = 1600

      [ui.window.box]
      h_align = "center"
      v_align = "center"
      orientation = "vertical"
      h_expand = true
      width = 920

      [ui.window.box.bar]
      orientation = "horizontal"
      position = "end"

      [ui.window.box.bar.entry]
      h_align = "fill"
      h_expand = true

      [ui.window.box.bar.entry.icon]
      h_align = "center"
      h_expand = false
      pixel_size = 16

      [ui.window.box.search]
      orientation = "horizontal"
      spacing = 4

      [ui.window.box.search.margins]
      bottom = 6

      [ui.window.box.search.prompt]
      name = "prompt"
      icon = "edit-find"
      h_align = "center"
      v_align = "center"

      [ui.window.box.search.clear]
      name = "clear"
      icon = "edit-clear"
      h_align = "center"
      v_align = "center"

      [ui.window.box.search.input]
      h_align = "fill"
      h_expand = true
      icons = true

      [ui.window.box.search.spinner]
      hide = true

      [ui.window.box.scroll]
      overlay_scrolling = true

      [ui.window.box.scroll.list]
      max_height = 700
      width = 920

      [ui.window.box.scroll.list.item]
      h_align = "fill"
      v_align = "fill"

      [ui.window.box.scroll.list.item.activation_label]
      x_align = 0.5
      y_align = 0.5

      [ui.window.box.scroll.list.item.icon]
      h_align = "center"
      v_align = "center"

      [ui.window.box.scroll.list.item.text]
      h_align = "start"
      h_expand = true
      wrap = true
      x_align = 0
      v_align = "center"
    '';
  };

  xdg.configFile."walker/themes/large.css" = {
    text = ''
      @import url("default.css");

      #input,
      #password,
      #typeahead {
        background: transparent;
      }


    '';
  };

  programs.swaylock = {
    enable = false;
    settings = {
      color = "000000";
      font-size = 24;
      indicator-idle-visible = false;
      indicator-radius = 100;
      line-color = "ffffff";
      show-failed-attempts = true;
    };
  };





  # status bar
  programs.waybar = {
    # https://github.com/hyprwm/Hyprland/discussions/1729
    #package = pkgs.unstable.waybar;

    enable = true;
    systemd = {
      enable = true;
    };
    settings.mainBar = {
      layer = "top"; # Waybar at top layer
      position = "top"; # Waybar at the bottom of your screen
      height = 24; # Waybar height
      # width = 1366; // Waybar width
      modules-left = [ "hyprland/workspaces" "custom/spotify" ];
      modules-center = [ "hyprland/window" ];
      modules-right = [ "custom/calendar" "custom/vpn" "pulseaudio" "network" "cpu" "memory" "battery" "tray" "clock" ];

      "custom/calendar" = {
        format = "{}";
        return-type = "json";
        interval = 60;
        exec = "${config.home.homeDirectory}/.local/bin/khal-waybar";
        on-click = "kitty --class floating-calendar -o confirm_os_window_close=0 -e khal interactive";
        on-click-right = "${config.home.homeDirectory}/.local/bin/khal-notify";
      };

      "custom/vpn" = {
        format = "{}";
        return-type = "json";
        interval = 5;
        exec = "vpn-waybar";
        on-click = "vpn-menu";
      };

      "hyprland/window" = {
        format = "{}";
        rewrite = {
          "(.*) — Mozilla Firefox" = "$1";
        };
        separate-outputs = true;
      };

      #https://github.com/Alexays/Waybar/wiki/Module:-Hyprland
      "hyprland/workspaces" = {
        format = "{icon}";
        active-only = false;
        on-click = "activate";
        format-icons = {
          active = "";
          default = "";
          "1" = "1";
          "2" = "2";
          "3" = "3";
          "4" = "4";
          "5" = "5";
          "6" = "6";
        };
      };

      tray = {
        # icon-size = 21;
        spacing = 10;
      };

      clock = {
        format-alt = "{:%Y-%m-%d}";
      };

      cpu = {
        format = "{usage}%   ";
      };

      memory = {
        format = "{}%   ";
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
        format-wifi = "{essid} ({signalStrength}%)   ";
        format-ethernet = "{ifname} ";
        format-disconnected = "Disconnected ⚠";
      };

      pulseaudio = {
        # scroll-step = 1;
        format = "{volume}% {icon} ";
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
        format = "   {}";
        max-length = 50;
        interval = 10; # Remove this if your script is endless and write in loop
        exec = "/home/flakm/.config/waybar/mediaplayer.sh 2> /dev/null"; # Script in resources folder
        exec-if = "pgrep spotify";
      };
    };

    style = ''
      * {
            border: none;
            border-radius: 0;
            font-family: "FiraCode Nerd Font";
            font-size: 13px;
            min-height: 0;
        }

        window#waybar {
            background: transparent;
            color: white;
        }

        #window {
            font-weight: bold;
            font-family: "FiraCode";
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
            /*color: rgb(102, 220, 105); */
        }

        #tray {
        }

        #custom-vpn {
            padding: 0 10px;
            margin: 0 4px;
            border-radius: 10px;
            font-weight: bold;
        }

        #custom-vpn.both {
            background: #00ff99;
            color: #000;
            font-weight: bold;
        }

        #custom-vpn.pritunl {
            background: #00ff99;
            color: #000;
            font-weight: bold;
        }

        #custom-vpn.tailscale {
            background: #33ccff;
            color: #000;
            font-weight: bold;
        }

        #custom-vpn.disconnected {
            background: #ff6b6b;
            color: #000;
            font-weight: bold;
        }

        #custom-calendar {
            padding: 0 10px;
            margin: 0 4px;
            border-radius: 10px;
            color: #fff;
        }

        #custom-calendar.has-events {
            background: #33ccff;
            color: #000;
            font-weight: bold;
        }

        #custom-calendar.urgent {
            background: #ff6b6b;
            color: #000;
            font-weight: bold;
        }

        #custom-calendar.no-events {
            color: #888;
        }
    '';
  };

  wayland.windowManager.hyprland = {
    enable = true;
    systemd = {
      enable = true;
      variables = [ "--all" ];
      enableXdgAutostart = true; # 🔑 start XDG‐autostart apps
    };
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };



  programs.hyprlock = {
    enable = true;
    settings =
      {
        general = {
          after_sleep_cmd = "hyprctl dispatch dpms on";
          before_sleep_cmd = "hyprctl dispatch dpms on";
          ignore_dbus_inhibit = false;
          lock_cmd = "hyprlock";
          # show a blurred screenshot background
          blur-background = "yes";
          blur-radius = 15;
          font = "FiraCode Nerd Font";
          disable_loading_bar = true;
          grace = 2;
          hide_cursor = true;
          no_fade_in = false;
        };
        background = [
          {
            path = "screenshot";
            blur_passes = 3;
            blur_size = 8;
          }
        ];


        label =
          {
            # hourly clock
            text = "cmd[update:1000] date +\"%-I:%M %p\"";
            position = "top";
          };

        input-field = [
          {
            size = "400, 50";
            position = "0, -80";
            monitor = "";
            dots_center = true;
            fade_on_empty = false;
            font_color = "rgb(202, 211, 245)";
            inner_color = "rgb(91, 96, 120)";
            outer_color = "rgb(24, 25, 38)";
            outline_thickness = 5;
            placeholder_text = "Password...";
            shadow_passes = 2;
          }
        ];


        listener = [];
      };
  };


  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
        ignore_dbus_inhibit = false;
      };
      listener = [
        {
          timeout = 300;  # 5 minutes - lock screen
          on-timeout = "hyprlock";
        }
        {
          timeout = 600;  # 10 minutes - turn off displays
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };

  };

  wayland.windowManager.hyprland.extraConfig = ''
        # See https://wiki.hyprland.org/Configuring/Monitors/

        env = XCURSOR_SIZE,32

        # toolkit-specific scaling
        xwayland {
          force_zero_scaling = true
        }

        debug {
            disable_logs = false
        }

        misc {
            mouse_move_enables_dpms = true
            key_press_enables_dpms = true
            disable_hyprland_logo = true
            disable_splash_rendering = true
            force_default_wallpaper = 0
            vfr = true
            vrr = 0
        }

        # For all categories, see https://wiki.hyprland.org/Configuring/Variables/
        input {
            kb_layout = pl
            kb_variant =
            kb_model =
            kb_rules =
            # both left windows and ctrl should be ctrl (caps lock is ctrl)
            kb_options = altwin:ctrl_win,ctrl:nocaps
    
            follow_mouse = 1
    
            touchpad {
                natural_scroll = no
            }
    
            sensitivity = 0 # -1.0 - 1.0, 0 means no modification.
        }
    
        general {
            # See https://wiki.hyprland.org/Configuring/Variables/ for more
            gaps_in = 5
            gaps_out = 10
            border_size = 5
            col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
            col.inactive_border = rgba(595959aa)
            layout = master
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
    
        decoration {
            rounding = 10
            blur {
                enabled = true
                size = 8
                passes = 1
            }
        }
    
        dwindle {
            # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
            pseudotile = yes # master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
            preserve_split = yes # you probably want this
            force_split = 2 # 0 (default): split follows mouse, 1: always split to left/top, 2: always split to right/bottom
        }

        master {
            # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
            new_status = slave # new windows go to slave stack (sides), not master (center)
            new_on_top = true # new windows are added to the top of the stack
            mfact = 0.55 # master window size ratio (0.5 = 50%)
            orientation = center # center: master in middle, slaves alternate sides (left first is hardcoded)
        }
    

        # Clipboard manager handled by CopyQ
        exec-once = copyq --start-server
        exec-once = walker --gapplication-service
        exec-once = ${configure-gtk-dark}/bin/configure-gtk-dark
        exec-once = hyprpaper
        exec-once = swaync

        # Critical for screen sharing - update DBUS environment
        exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland


        windowrule = workspace 2,title:^(Firefox)(.*)$
        exec-once=[workspace 1 silent] kitty
        exec-once=[workspace 2 silent] uwsm app -- firefox

        # Transparency via Hyprland
        # windowrulev2 = opacity 0.90, class:^(kitty)$
        windowrulev2 = opacity 0.90, class:^(firefox)$
        windowrulev2 = opacity 0.80, class:^(spotify)$

        # Floating calendar window
        windowrulev2 = float, class:^(floating-calendar)$
        windowrulev2 = size 1400 900, class:^(floating-calendar)$
        windowrulev2 = center, class:^(floating-calendar)$

        exec-once=[workspace 3 silent] obsidian
        exec-once=[workspace 3 silent] kitty --title "obsidian" --directory /home/flakm/programming/flakm/obsidian/work -- bash -c "tmux new-session -d -s obsidian 'nvim' && tmux attach-session -t obsidian"
        windowrulev2 = float, title:^(obsidian)$
        windowrulev2 = fullscreen, title:^(obsidian)$

        exec-once=[workspace 4 silent] spotify
        exec-once=[workspace 6 silent] kdeconnect-app
        exec-once=[workspace 4 silent] spotify

        exec-once=[workspace 9 silent] thunderbird
        exec-once=[workspace 10 silent] slack


        # See https://wiki.hyprland.org/Configuring/Keywords/ for more
        $mainMod = ALT

        bind=ALT_SHIFT,Q,killactive,
    
        bind=$mainMod,F,fullscreen 

        bind = $mainMod, D, exec, walker --modules applications
        bind = ALT_CTRL, N, exec, ${config.home.homeDirectory}/.config/theme-switch.sh
        bind = $mainMod SHIFT, W, exec, hyprctl hyprpaper wallpaper "DP-1,${config.home.homeDirectory}/.config/wallpaper.png" 
        bind = $mainMod SHIFT, RETURN, exec, kitty

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

        # Focus movement
        bind=CTRL SHIFT,h,movefocus,l
        bind=CTRL SHIFT,l,movefocus,r
        bind=CTRL SHIFT,k,movefocus,u
        bind=CTRL SHIFT,j,movefocus,d

        # Window movement
        bind = $mainMod CTRL, H, movewindow, l
        bind = $mainMod CTRL, L, movewindow, r
        bind = $mainMod CTRL, K, movewindow, u
        bind = $mainMod CTRL, J, movewindow, d

        # Resize windows
        bind = $mainMod CTRL SHIFT, l, resizeactive, 100 0
        bind = $mainMod CTRL SHIFT, h, resizeactive, -100 0
        bind = $mainMod CTRL SHIFT, k, resizeactive, 0 -100
        bind = $mainMod CTRL SHIFT, j, resizeactive, 0 100

        # Clipboard actions
        # alt+v to open clipboard history (changed from ctrl+shift+v to avoid conflicts)
        bind = $mainMod, V, exec, walker --modules clipboard
        # alt+. to open emoji picker
        bind = $mainMod, period, exec, rofimoji | wl-copy


        # print screen full screen
        bind=,Print,exec,grimblast --scale 2 --wait 2 copy screen
        # print screen selection range
        bind=SHIFT,Print,exec,grimblast --scale 2 copy area
        # print screen with 3s delay and area selection (freeze shows animation)
        bind=CTRL SHIFT,Print,exec,grimblast --scale 2 --freeze copy area
        # save screenshot to Pictures with timestamp
        bind=$mainMod,Print,exec,grimblast --scale 2 --wait 2 save area ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png

        bind=$mainMod SHIFT, L, exec, hyprlock
        bind = $mainMod, N, exec, swaync-client -t -sw


        # volume button that allows press and hold, volume limited to 150%
        binde=, XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+
        binde=, XF86AudioLowerVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%-
        bind=, XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        
        # media controls
        bind=, XF86AudioPlay, exec, playerctl play-pause
        bind=, XF86AudioNext, exec, playerctl next
        bind=, XF86AudioPrev, exec, playerctl previous
        
        # brightness controls
        binde=SHIFT, F12, exec, ddcutil setvcp 10 + 10
        binde=SHIFT, F11, exec, ddcutil setvcp 10 - 10

  '';


}
