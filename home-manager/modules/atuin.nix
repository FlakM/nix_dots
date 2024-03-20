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
    };
  };

}
