{ inputs, config, pkgs, pkgs-unstable, pkgs-master, libs, lib, ... }:
let

  ## xdg-open shim that proxies to handlr
  xdg-open = pkgs.writeScriptBin "xdg-open" ''
    #!/usr/bin/env bash
    handlr open "$@"
  '';
  alacritty-wrapped = pkgs-master.alacritty.overrideAttrs (old: {
    postPatch = ''
      substituteInPlace alacritty/src/config/ui_config.rs \
        --replace xdg-open ${xdg-open}/bin/xdg-open
    '';
  });
  settings = {
    # copied from:
    # https://github.com/alexghr/alacritty-theme.nix
    # themes are from:
    # https://github.com/alacritty/alacritty-theme

    live_config_reload = true;

    env = {
      TERM = "xterm-256color";
    };
    hide_cursor_when_typing = true;
    font = {
      normal.family = "RobotoMono Nerd Font";
      bold.family = "RobotoMono Nerd Font";
      italic.family = "RobotoMono Nerd Font";
      # Offset is the extra space around each character. offset.y can be thought of
      # as modifying the linespacing, and offset.x as modifying the letter spacing.
      offset = {
        x = 0;
        y = 0;
      };

      # Glyph offset determines the locations of the glyphs within their cells with
      # the default being at the bottom. Increase the x offset to move the glyph to
      # the right, increase the y offset to move the glyph upward.
      glyph_offset = {
        x = 0;
        y = 0;
      };
    };
    window.padding = {
      x = 2;
      y = 2;
    };

    shell.program = "${pkgs.zsh}/bin/zsh";

    cursor.style = "Beam";

  };

  # https://github.com/alacritty/alacritty-theme/blob/0fb8868d6389014fd551851df7153e4ca2590790/themes/night_owlish_light.yaml
  light_theme = {
    colors = {
      bright = {
        black = "#7a8181";
        blue = "#5ca7e4";
        cyan = "#00c990";
        green = "#49d0c5";
        magenta = "#697098";
        red = "#f76e6e";
        white = "#989fb1";
        yellow = "#dac26b";
      };
      cursor = {
        cursor = "#403f53";
        text = "#fbfbfb";
      };
      normal = {
        black = "#011627";
        blue = "#4876d6";
        cyan = "#08916a";
        green = "#2aa298";
        magenta = "#403f53";
        red = "#d3423e";
        white = "#7a8181";
        yellow = "#daaa01";
      };
      primary = {
        background = "#ffffff";
        foreground = "#403f53";
      };
      selection = {
        background = "#f2f2f2";
        text = "#403f53";
      };
    };
  };

  # https://github.com/alacritty/alacritty-theme/blob/0fb8868d6389014fd551851df7153e4ca2590790/themes/argonaut.yaml
  dark_theme = {
    colors = {
      primary = {
        background = "0x292C3E";
        foreground = "0xEBEBEB";
      };
      cursor = {
        text = "0xEBEBEB";
        cursor = "0xFF261E";
      };
      normal = {
        black = "0x0d0d0d";
        red = "0xFF301B";
        green = "0xA0E521";
        yellow = "0xFFC620";
        blue = "0x1BA6FA";
        magenta = "0x8763B8";
        cyan = "0x21DEEF";
        white = "0xEBEBEB";
      };
      bright = {
        black = "0x6D7070";
        red = "0xFF4352";
        green = "0xB8E466";
        yellow = "0xFFD750";
        blue = "0x1BA6FA";
        magenta = "0xA578EA";
        cyan = "0x73FBF1";
        white = "0xFEFEF8";
      };
    };
  };
in
{
  xdg.configFile."alacritty/dark_alacritty.yml".source = (pkgs.formats.yaml { }).generate "alacritty-config" (dark_theme // settings);
  xdg.configFile."alacritty/light_alacritty.yml".source = (pkgs.formats.yaml { }).generate "alacritty-config" (light_theme // settings);

  #home.packages = with pkgs; [
  #  alacritty
  #];
  xdg.configFile."alacritty/switch.sh" = {
    text = ''
      #!/usr/bin/env bash
      color=$1
      path=$2

      function dark() {
        cat ~/.config/alacritty/dark_alacritty.yml > ~/.config/alacritty/alacritty.yml
      }

      function light() {
        cat ~/.config/alacritty/light_alacritty.yml > ~/.config/alacritty/alacritty.yml
      }

      if [ "$color" = "dark" ]; then
        dark
      elif [ "$color" = "light" ]; then
        light
      else
        if grep -q "prefer-dark" $path; then
          dark
        else
          light
        fi
      fi
    '';
    executable = true;
  };



  home.packages = [
    alacritty-wrapped
    #pkgs.master.alacritty
  ];


  xdg.dataFile."applications/neomutt.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=neomutt-desktop
    Categories=Email
    Exec=${alacritty-wrapped}/bin/alacritty -T Email neomutt %u
    StartupNotify=true
    MimeType=x-scheme-handler/mailto;
  '';

  xdg.mimeApps.defaultApplications."x-scheme-handler/mailto" =
    [ "neomutt.desktop" ];


}

