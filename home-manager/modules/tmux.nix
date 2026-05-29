{ config, pkgs, pkgsUnstable, libs, ... }:
{

  home.packages = with pkgs; [
    tmux
  ];

  home.sessionVariables =
    {
      TMUX_FZF_OPTIONS = "-p -w 90% -h 60% -m";
    };

  # ── tmux status-bar palettes — mirror the kitty dark/light/sunlight themes.
  # kitty/switch.sh copies the matching one to current-theme.conf and reloads
  # tmux live, so the bar tracks the same toggle as kitty/delta/aerc.
  xdg.configFile."tmux/themes/dark.conf".text = ''
    # dark — GitHub Dark High Contrast
    set -g status-style "bg=#161b22,fg=#8b949e"
    set -g @thm_bg "#0d1117"
    set -g @thm_panel "#161b22"
    set -g @thm_fg "#e6edf3"
    set -g @thm_muted "#8b949e"
    set -g @thm_accent "#79c0ff"
    set -g @thm_warn "#e3b341"
    set -g message-style "bg=#161b22,fg=#e6edf3"
    set -g message-command-style "bg=#161b22,fg=#e6edf3"
    set -g mode-style "bg=#264f78,fg=#e6edf3"
    set -g pane-border-style "fg=#30363d"
    set -g pane-active-border-style "fg=#79c0ff"
    set -g menu-style "bg=#161b22,fg=#e6edf3"
    set -g menu-selected-style "bg=#264f78,fg=#e6edf3,bold"
    set -g menu-border-style "fg=#30363d"
    set -g popup-style "bg=#0d1117"
    set -g popup-border-style "fg=#30363d"
  '';

  xdg.configFile."tmux/themes/light.conf".text = ''
    # light — Bluloco Light
    set -g status-style "bg=#E6E5E5,fg=#929396"
    set -g @thm_bg "#f9f9f9"
    set -g @thm_panel "#E6E5E5"
    set -g @thm_fg "#373a41"
    set -g @thm_muted "#929396"
    set -g @thm_accent "#275fe4"
    set -g @thm_warn "#df631c"
    set -g message-style "bg=#E6E5E5,fg=#373a41"
    set -g message-command-style "bg=#E6E5E5,fg=#373a41"
    set -g mode-style "bg=#DAF1FF,fg=#373a41"
    set -g pane-border-style "fg=#cccccc"
    set -g pane-active-border-style "fg=#275fe4"
    set -g menu-style "bg=#E6E5E5,fg=#373a41"
    set -g menu-selected-style "bg=#DAF1FF,fg=#275fe4,bold"
    set -g menu-border-style "fg=#cccccc"
    set -g popup-style "bg=#f9f9f9"
    set -g popup-border-style "fg=#cccccc"
  '';

  xdg.configFile."tmux/themes/sunlight.conf".text = ''
    # sunlight — warm cream
    set -g status-style "bg=#ddd8d0,fg=#767676"
    set -g @thm_bg "#f5f0e8"
    set -g @thm_panel "#ddd8d0"
    set -g @thm_fg "#1c1c1c"
    set -g @thm_muted "#767676"
    set -g @thm_accent "#0060c0"
    set -g @thm_warn "#c06000"
    set -g message-style "bg=#ddd8d0,fg=#1c1c1c"
    set -g message-command-style "bg=#ddd8d0,fg=#1c1c1c"
    set -g mode-style "bg=#b3d4f0,fg=#1c1c1c"
    set -g pane-border-style "fg=#c0bbb3"
    set -g pane-active-border-style "fg=#0060c0"
    set -g menu-style "bg=#ddd8d0,fg=#1c1c1c"
    set -g menu-selected-style "bg=#b3d4f0,fg=#0060c0,bold"
    set -g menu-border-style "fg=#c0bbb3"
    set -g popup-style "bg=#f5f0e8"
    set -g popup-border-style "fg=#c0bbb3"
  '';


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

      # ── Quality-of-life ──
      set -g mouse off                # off by default so the terminal keeps native selection/scroll
      bind m set -g mouse \; display "mouse #{?mouse,on,off}"  # toggle when you want pane resize/scroll
      set -g renumber-windows on      # no gaps in window numbers after closing one
      set -g history-limit 50000      # deeper scrollback for fuzzback
      set -g detach-on-destroy off    # killing a session drops to the next, not out

      # Splits inherit the current pane's directory
      bind "|" split-window -h -c "#{pane_current_path}"
      bind "-" split-window -v -c "#{pane_current_path}"

      # Reload config
      bind R source-file ~/.config/tmux/tmux.conf \; display "config reloaded"

      set -g default-terminal "tmux-256color"
      #set -ag terminal-overrides ",xterm-256color:RGB"

      set-option -a terminal-overrides ",kitty:RGB"

      # ── Status bar (theme-aware: kitty/switch.sh swaps the palette + reloads) ──
      set -g status on
      set -g status-interval 30
      set -g status-justify left
      set -g status-left-length 40
      set -g status-right-length 60

      # Dark defaults so the bar renders before switch.sh has written a theme
      set -g status-style "bg=#161b22,fg=#8b949e"
      set -g @thm_bg "#0d1117"
      set -g @thm_panel "#161b22"
      set -g @thm_fg "#e6edf3"
      set -g @thm_muted "#8b949e"
      set -g @thm_accent "#79c0ff"
      set -g @thm_warn "#e3b341"

      set -g status-left "#[fg=#{@thm_bg},bg=#{@thm_accent},bold] #S #[fg=#{@thm_accent},bg=#{@thm_panel}]#{?client_prefix,#[fg=#{@thm_bg}#,bg=#{@thm_warn}#,bold] PREFIX #[default],} "
      set -g window-status-format "#[fg=#{@thm_muted}] #I #W "
      set -g window-status-current-format "#[fg=#{@thm_accent},bold] #I #W "
      set -g window-status-separator ""
      set -g status-right "#[fg=#{@thm_muted}] #H #[fg=#{@thm_fg},bold] %H:%M "

      # ── Active pane: heavy accent border + arrow indicator ──
      set -g pane-border-lines heavy
      set -g pane-border-indicators arrows

      # ── Menu/popup defaults (dark; themes override on switch) ──
      set -g menu-style "bg=#161b22,fg=#e6edf3"
      set -g menu-selected-style "bg=#264f78,fg=#e6edf3,bold"
      set -g menu-border-style "fg=#30363d"
      set -g menu-border-lines rounded
      set -g popup-style "bg=#0d1117"
      set -g popup-border-style "fg=#30363d"
      set -g popup-border-lines rounded

      # Live theme written by kitty/switch.sh on dark/light/sunlight flip
      source-file -q ~/.config/tmux/current-theme.conf

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

      # tmux-thumbs — Vimium-style hint labels to grab paths/hashes/urls.
      # prefix + g (default 'space' clobbers next-layout). Copy routes through
      # set-buffer -w so the OSC 52 clipboard config above picks it up.
      set -g @thumbs-key g
      set -g @thumbs-command 'tmux set-buffer -w -- {} && tmux display-message "copied: {}"'
      # Named colors resolve through the terminal palette, so the hints track
      # the active kitty dark/light/sunlight theme automatically.
      set -g @thumbs-fg-color cyan          # grabbable tokens tinted cyan
      set -g @thumbs-hint-bg-color yellow   # label key: black on gold block
      set -g @thumbs-hint-fg-color black
      set -g @thumbs-select-fg-color green  # focused match in multi-select
      set -g @thumbs-contrast 1             # bracket the labels for clarity
      run-shell ${pkgs.tmuxPlugins.tmux-thumbs}/share/tmux-plugins/tmux-thumbs/tmux-thumbs.tmux

      bind-key -n "C-l" run-shell -b "${pkgs.tmuxPlugins.tmux-fzf}/share/tmux-plugins/tmux-fzf/scripts/session.sh switch"

      
    '';

    shell = "${pkgs.zsh}/bin/zsh";
    plugins = with pkgs.tmuxPlugins; [ sensible yank fuzzback tmux-fzf tmux-thumbs ];

  };

}
