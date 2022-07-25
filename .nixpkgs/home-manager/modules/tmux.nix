
{ config, pkgs, pkgsUnstable, libs, ... }:
{

  home.packages = with pkgs; [
     tmux
  ];

  programs.tmux = {
    enable = true;
    clock24 = true;

    extraConfig = ''
    # Start windows and pane numbering with index 1 instead of 0
    set -g base-index 1
    setw -g pane-base-index 1
    # {n}vim compability
    set-option -ga terminal-overrides ",xterm-256color:Tc"
    set -g default-terminal "screen-256color"
    set-option -g status-style bg=default
    '';
    plugins = with pkgs.tmuxPlugins; [ sensible yank];

  };

}
