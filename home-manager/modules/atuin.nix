{ pkgs-unstable, ... }:
{
  # to address a slow startup sometimes
  # go to https://github.com/atuinsh/atuin/issues/952 
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    package = pkgs-unstable.atuin;
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
    };
  };

}
