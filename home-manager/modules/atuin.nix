{ config, pkgs, pkgsUnstable, libs, ... }: {

  programs.atuin = {
    enable = true;
    package = pkgs.unstable.atuin;
    enableZshIntegration = true;
    settings = {
      filter_mode_shell_up_key_binding = "session";
      auto_sync = true;
      sync_frequency = "5m";
      style = "compact";
      search_mode = "fuzzy";
    };
  };

}
