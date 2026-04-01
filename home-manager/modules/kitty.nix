{ config, pkgs, pkgs-unstable, lib, libs, ... }:
let
  kitty = pkgs-unstable.kitty;
  url-open = pkgs.writeScriptBin "url-open" ''
    #!/usr/bin/env bash
    exec ${if pkgs.stdenv.isDarwin then "/usr/bin/open" else "${pkgs.handlr}/bin/handlr open"} "$@"
  '';
  xdg-open = pkgs.writeScriptBin "xdg-open" ''
    #!/usr/bin/env bash
    exec ${url-open}/bin/url-open "$@"
  '';
in
{

  home.packages = lib.optionals pkgs.stdenv.isLinux [ xdg-open ];

  xdg.configFile."kitty/switch.sh" = {
    text = ''
      #!/usr/bin/env bash
      color=$1
      path=$2

      function dark() {
        echo "dark"
        ${kitty}/bin/kitten themes --config-file-name=my "GitHub Dark High Contrast"
        { cat "${config.home.homeDirectory}/Library/Preferences/aerc/stylesets/dark" > "${config.home.homeDirectory}/Library/Preferences/aerc/stylesets/current"; } 2>/dev/null || true
      }

      function light() {
        echo "light"
        ${kitty}/bin/kitten themes --config-file-name=my "Bluloco Light"
        { cat "${config.home.homeDirectory}/Library/Preferences/aerc/stylesets/light" > "${config.home.homeDirectory}/Library/Preferences/aerc/stylesets/current"; } 2>/dev/null || true
      }


      if [ ! -f ~/.config/delta/theme ]; then
        mkdir -p ~/.config/delta
        touch ~/.config/delta/theme
        light
      fi

      if [ "$color" = "dark" ]; then
        echo "dark-mode --dark" > ~/.config/delta/theme
        dark
      elif [ "$color" = "light" ]; then
        echo "light-mode" > ~/.config/delta/theme
        light
      else
        if grep -q "prefer-dark" $path; then
          dark
        else
          light
        fi
      fi
      pkill -SIGUSR1 kitty || pkill -a -SIGUSR1 kitty || true


    '';
    executable = true;
  };

  programs.kitty = {
    package = kitty;
    enable = true;
    shellIntegration.enableZshIntegration = true;

    extraConfig = ''
      include current-theme.conf
      open_url_with ${url-open}/bin/url-open
      # Allow neovim jump to last cursor position
      map ctrl+shift+o no_op
      map ctrl+shift+n no_op
      map ctrl+shift+p no_op
      # Enable bracketed paste mode for safe multiline pasting
      paste_actions quote-urls-at-prompt
      copy_on_select no
      clipboard_control write-primary write-clipboard read-clipboard no-append
      map shift+insert paste_from_clipboard
      map alt+shift+c copy_to_clipboard
      map alt+shift+v paste_from_clipboard
    '';

    font = {
      name = "FiraCode Nerd Font Mono";
      package =
        pkgs.nerd-fonts.fira-code;
    };
  };


}
