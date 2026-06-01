{ pkgs-unstable, ... }:
{
  programs.atuin = {
    enable = true;
    enableZshIntegration = false;
    package = pkgs-unstable.atuin;
    # Daemon owns the sqlite writes (out of the shell hot-path), which removes
    # the ZFS fsync latency the rpool/nixos/atuin zvol used to work around.
    daemon.enable = true;
    # https://github.com/atuinsh/atuin/issues/1199#issuecomment-1940931241
    settings = {
      sync = {
        records = true;
      };
      # use this to disable auto sync
      auto_sync = true;

      filter_mode_shell_up_key_binding = "session";

      # use ctrl instead of alt as the shortcut modifier key for numerical UI shortcuts
      ctrl_n_shortcuts = true;
      keymap_mode = "vim-insert";
    };
  };

}
