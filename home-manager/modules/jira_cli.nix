{ config, pkgs, pkgsUnstable, libs, ... }:
{

  home.packages = with pkgs; [
    jira-cli-go
  ];


}
