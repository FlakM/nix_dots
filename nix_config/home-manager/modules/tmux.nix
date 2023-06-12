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
      # https://stackoverflow.com/questions/60309665/neovim-colorscheme-does-not-look-right-when-using-nvim-inside-tmux
      set-option -ga terminal-overrides ",xterm-256color:Tc"

      set -g default-terminal "screen-256color"
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
    plugins = with pkgs.tmuxPlugins; [ sensible yank ];

  };

}
