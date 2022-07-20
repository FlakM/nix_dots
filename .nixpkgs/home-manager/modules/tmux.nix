
{ config, pkgs, pkgsUnstable, libs, ... }:
{

  
  
  home.packages = with pkgs; [
     tmux
  ];


  programs.tmux = {
    enable = true;
    clock24 = true;
  };

}
