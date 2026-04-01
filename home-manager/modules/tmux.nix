{ config, pkgs, pkgsUnstable, libs, ... }:
{

  home.packages = with pkgs; [
    tmux
  ];

  home.sessionVariables =
    {
      TMUX_FZF_OPTIONS = "-p -w 90% -h 60% -m";
    };


  programs.tmux = {
    enable = true;
    clock24 = true;

    extraConfig = ''
      # Start windows and pane numbering with index 1 instead of 0
      set-option -g default-shell /run/current-system/sw/bin/zsh
      set-option -g default-command /run/current-system/sw/bin/zsh

      set -ga update-environment WAYLAND_DISPLAY

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

      # Clipboard via OSC 52 — works both locally and over SSH
      # tmux sends OSC 52 to the terminal on yank, kitty picks it up
      set -g set-clipboard on
      set -g allow-passthrough on
      set -as terminal-features ',xterm-kitty:clipboard'

      bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
      bind-key -T copy-mode-vi Enter send-keys -X copy-selection-and-cancel
      bind ] paste-buffer -p

      # Shift+Insert paste from system clipboard
      # kitty's map is bypassed when apps use the kitty keyboard protocol,
      # so we handle it explicitly in tmux
      bind-key -n S-Insert run-shell 'tmux set-buffer -- "$(wl-paste -n 2>/dev/null || pbpaste 2>/dev/null)"; tmux paste-buffer -p'

      # Enable focus events for Neovim
      set -g focus-events on

      # Set escape time to avoid delay in Neovim
      set -sg escape-time 10

      run-shell ${pkgs.tmuxPlugins.fuzzback}/share/tmux-plugins/fuzzback/fuzzback.tmux
      set -g @fuzzback-popup 1

      bind-key -n "C-l" run-shell -b "${pkgs.tmuxPlugins.tmux-fzf}/share/tmux-plugins/tmux-fzf/scripts/session.sh switch"

      
    '';

    shell = "${pkgs.zsh}/bin/zsh";
    plugins = with pkgs.tmuxPlugins; [ sensible yank fuzzback tmux-fzf ];

  };

}
