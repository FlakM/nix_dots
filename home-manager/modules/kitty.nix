{ config, pkgs, pkgs-unstable, libs, ... }:
let kitty = pkgs-unstable.kitty;
in
{

  xdg.configFile."kitty/switch.sh" = {
    text = ''
      #!/usr/bin/env bash
      color=$1
      path=$2

      function dark() {
        echo "dark"
        ${kitty}/bin/kitten themes --config-file-name=my "GitHub Dark High Contrast"
      }

      function light() {
        echo "light"
        ${kitty}/bin/kitten themes --config-file-name=my Material
      }


      if [ ! -f ~/.config/delta/theme ]; then
        mkdir -p ~/.config/delta
        touch ~/.config/delta/theme
        light
      fi

      if [ "$color" = "dark" ]; then
        echo "dark-mode" > ~/.config/delta/theme
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
      ${pkgs.toybox}/bin/pkill -SIGUSR1 kitty


    '';
    executable = true;
  };

  programs.kitty = {
    package = kitty;
    enable = true;
    shellIntegration.enableZshIntegration = true;

    extraConfig = "
    include current-theme.conf
    # Allow neovim jump to last cursor position
    map ctrl+shift+o no_op
    ";

    font = {
      name = "FiraCode Nerd Font Mono";
      package = pkgs.nerdfonts;
    };
  };
}

