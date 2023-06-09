{ config, pkgs, pkgsUnstable, libs, ... }:
{


  home.packages = with pkgs; [
    alacritty
  ];


  programs.alacritty = {
    enable = true;
    settings = {
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

      # copied from:
      # https://github.com/eendroroy/alacritty-theme/blob/master/themes/argonaut.yaml
      colors = {
        primary = {
          background = "0x292C3E";
          foreground = "0xEBEBEB";
        };
        cursor = {
          text = "0xFF261E";
          cursor = "0xFF261E";
        };

        normal = {
          black = "0x0d0d0d";
          red = "0xFF301B";
          green = "0xA0E521";
          yellow = "0xFFC620";
          blue = "0x1BA6FA";
          magneta = "0x8763B8";
          cyan = "0x21DEEF";
          white = "0xEBEBEB";
        };

        bright = {
          black = "0x6D7070";
          red = "0xFF4352";
          green = "0xB8E466";
          yellow = "0xFFD750";
          blue = "0x1BA6FA";
          magneta = "0xA578EA";
          cyan = "0x73FBF1";
          white = "0xFEFEF8";
        };

        dim = {
          black = "0x9E9F9F";
          red = "0x864343";
          green = "0x777c44";
          yellow = "0x9e824c";
          blue = "0x556a7d";
          magenta = "0x75617b";
          cyan = "0x5b7d78";
          white = "0x828482";
        };

      };
      selection.semantic_escape_chars = ",?`|:\"' ()[]{}<>";
    };
  };

}

