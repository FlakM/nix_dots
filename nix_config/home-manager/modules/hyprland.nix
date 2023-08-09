{ config, pkgs, ... }: {

  # define session variables

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = 1; # Firefox Wayland
  };


  home.packages = with pkgs; [
    tofi
  ];

  wayland.windowManager.hyprland.extraConfig = ''
    $mod = SUPER

    bind = $mod, F, exec, firefox
    bind = $mod, D, exec, tofi
    bind = , Print, exec, grimblast copy area

    # workspaces
    # binds $mod + [shift +] {1..10} to [move to] workspace {1..10}
    ${builtins.concatStringsSep "\n" (builtins.genList (
        x: let
          ws = let
            c = (x + 1) / 10;
          in
            builtins.toString (x + 1 - (c * 10));
        in ''
          bind = $mod, ${ws}, workspace, ${toString (x + 1)}
          bind = $mod SHIFT, ${ws}, movetoworkspace, ${toString (x + 1)}
        ''
      )
      10)}

    # ...
  '';

}
