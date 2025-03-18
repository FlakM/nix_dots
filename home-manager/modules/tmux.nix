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
      set-option -g default-shell /run/current-system/sw/bin/zsh
      set-option -g default-command /run/current-system/sw/bin/zsh

      set -g base-index 1
      setw -g pane-base-index 1

      set -g default-terminal "tmux-256color"
      #set -ag terminal-overrides ",xterm-256color:RGB"

      set-option -a terminal-overrides ",kitty:RGB"

      set-option -g status-style bg=default

      # to enter press prefix + [
      setw -g mode-keys vi

      # use hjkl to navigate between panes
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      set -s set-clipboard on
    '';

    shell = "${pkgs.zsh}/bin/zsh";
    plugins = with pkgs.tmuxPlugins; [ sensible yank ];

  };

}
