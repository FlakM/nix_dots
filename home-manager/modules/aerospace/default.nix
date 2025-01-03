{ pkgs, config, ... }:


let
  path = "${config.home.homeDirectory}/.config/current-color_scheme";
  apply-theme-script = pkgs.writeScriptBin "apply-theme" ''
    #! ${pkgs.runtimeShell}
    # create an empty file if it doesn't exist
    if [ ! -f ${path} ]; then
      touch ${path}
      echo "prefer-light" > ${path}
    fi
    curr=$(cat ${path})
    
    function switch_theme() {
      echo $1 > ${path}
      echo "Current theme: cat ${path}"
    }

    if [ ! -f ${path} ]; then
      touch ${path}
      echo "prefer-light" > ${path}
    fi


    if [ "$curr" = "prefer-light" ]; then
      switch_theme "prefer-dark" || true
      ${config.home.homeDirectory}/.config/kitty/switch.sh dark ${path} || true
      ${configure-mac-dark}/bin/configure-mac-dark || true

      for server in $(nvr --serverlist); do
        echo "Setting background to dark for server: $server" >> /tmp/nvr.log
        nvr --servername "$server" -cc 'set background=dark'
      done
    else
      switch_theme "prefer-light" || true
      ${config.home.homeDirectory}/.config/kitty/switch.sh light ${path} || true

      ${configure-mac-light}/bin/configure-mac-light || true

      for server in $(nvr --serverlist); do
        echo "Setting background to light for server: $server" >> /tmp/nvr.log
        nvr --servername "$server" -cc 'set background=light'
      done
    fi
  '';
  configure-mac-dark = pkgs.writeTextFile {
    name = "configure-mac-dark";
    destination = "/bin/configure-mac-dark";
    executable = true;
    text =
      ''
        osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'
      '';
  };


  configure-mac-light = pkgs.writeTextFile {
    name = "configure-mac-light";
    destination = "/bin/configure-mac-light";
    executable = true;
    text =
      ''
        osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false'
      '';
  };

in


{
  # Source aerospace config from the home-manager store
  home.file.".aerospace.toml".source = ./config.toml;


  # apply-theme-script
  home.packages = [
    apply-theme-script
  ];
}
