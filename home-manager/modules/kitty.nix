{ config, pkgs, pkgs-unstable, lib, libs, ... }:
let
  kitty = pkgs-unstable.kitty;
  url-open = pkgs.writeScriptBin "url-open" ''
    #!/usr/bin/env bash
    exec ${if pkgs.stdenv.isDarwin then "/usr/bin/open" else "${pkgs.handlr}/bin/handlr open"} "$@"
  '';
  xdg-open = pkgs.writeScriptBin "xdg-open" ''
    #!/usr/bin/env bash
    exec ${url-open}/bin/url-open "$@"
  '';
  aerc = config.home.homeDirectory + "/Library/Preferences/aerc";
in
{

  home.packages = lib.optionals pkgs.stdenv.isLinux [ xdg-open ];

  # ── Kitty theme confs — written as files, switch.sh copies the right one ────
  xdg.configFile."kitty/themes/dark.conf".text = ''
    # dark — GitHub Dark High Contrast
    foreground            #e6edf3
    background            #0d1117
    selection_background  #264f78
    selection_foreground  #e6edf3
    cursor                #e6edf3
    cursor_text_color     #0d1117
    url_color             #79c0ff
    active_border_color   #79c0ff
    inactive_border_color #30363d
    wayland_titlebar_color #161b22
    macos_titlebar_color   #161b22
    active_tab_foreground   #e6edf3
    active_tab_background   #0d1117
    inactive_tab_foreground #8b949e
    inactive_tab_background #161b22
    tab_bar_background      #010409
    color0  #1c1c1c
    color8  #6e7681
    color1  #ff7b72
    color9  #ffa198
    color2  #56d364
    color10 #7ee787
    color3  #e3b341
    color11 #f2cc60
    color4  #79c0ff
    color12 #a5d6ff
    color5  #d2a8ff
    color13 #efb8ff
    color6  #56d4dd
    color14 #80deea
    color7  #b1bac4
    color15 #ffffff
  '';

  xdg.configFile."kitty/themes/light.conf".text = ''
    # light/white — Bluloco Light
    foreground            #373a41
    background            #f9f9f9
    selection_background  #DAF1FF
    selection_foreground  #373a41
    cursor                #f32759
    cursor_text_color     #373a41
    url_color             #275FE4
    active_border_color   #275FE4
    inactive_border_color #cccccc
    wayland_titlebar_color #ECECEC
    macos_titlebar_color   #ECECEC
    active_tab_foreground   #373a41
    active_tab_background   #f9f9f9
    inactive_tab_foreground #929396
    inactive_tab_background #E6E5E5
    tab_bar_background      #ECECEC
    color0  #373a41
    color8  #676a77
    color1  #d52753
    color9  #ff6480
    color2  #23974a
    color10 #3cbc66
    color3  #df631c
    color11 #c5a332
    color4  #275fe4
    color12 #0099e1
    color5  #823ff1
    color13 #ce33c0
    color6  #27618d
    color14 #6d93bb
    color7  #babbc2
    color15 #d3d3d3
  '';

  xdg.configFile."kitty/themes/sunlight.conf".text = ''
    # sunlight — warm cream, high contrast outdoor
    foreground            #1c1c1c
    background            #f5f0e8
    selection_background  #b3d4f0
    selection_foreground  #1c1c1c
    cursor                #0060c0
    cursor_text_color     #f5f0e8
    url_color             #0060c0
    active_border_color   #0060c0
    inactive_border_color #c0bbb3
    wayland_titlebar_color #d4cfc7
    macos_titlebar_color   #d4cfc7
    active_tab_foreground   #1c1c1c
    active_tab_background   #f5f0e8
    inactive_tab_foreground #767676
    inactive_tab_background #ddd8d0
    tab_bar_background      #d4cfc7
    color0  #1c1c1c
    color8  #4a4a4a
    color1  #cc0000
    color9  #dd1111
    color2  #006400
    color10 #007878
    color3  #c06000
    color11 #9b7800
    color4  #0060c0
    color12 #007aaa
    color5  #5500aa
    color13 #7700cc
    color6  #007878
    color14 #009090
    color7  #c8c3bb
    color15 #f5f0e8
  '';

  xdg.configFile."kitty/switch.sh" = {
    text = ''
      #!/usr/bin/env bash
      # Usage: switch.sh [dark|light|sunlight] [color-scheme-file]
      color=$1
      path=$2
      THEMES=~/.config/kitty/themes
      THEME_CONF=~/.config/kitty/current-theme.conf

      tmux_theme() {
        # Swap the tmux palette and live-reload any running server.
        # `install -m 0644` instead of `cp` — sources live in /nix/store (0444),
        # and cp preserves source mode, leaving the destination read-only so the
        # next switch silently no-ops.
        # Loop over both default socket dirs — when fired from hyprland's exec
        # dispatch the env has no TMUX_TMPDIR, so a bare `tmux` would hit
        # /tmp/tmux-UID/default and miss a session running under $XDG_RUNTIME_DIR.
        local variant=$1
        local uid; uid=$(id -u)
        mkdir -p ~/.config/tmux 2>/dev/null
        install -m 0644 ~/.config/tmux/themes/$variant.conf ~/.config/tmux/current-theme.conf 2>/dev/null || true
        for sock in "$XDG_RUNTIME_DIR/tmux-$uid/default" "/tmp/tmux-$uid/default"; do
          [ -S "$sock" ] && tmux -S "$sock" source-file ~/.config/tmux/current-theme.conf 2>/dev/null
        done
      }

      claude_theme() {
        # ~/.claude.json: absent/null = dark, "light" = light
        local mode=$1
        local f=~/.claude.json
        if [ -f "$f" ]; then
          local tmp
          tmp=$(mktemp)
          if [ "$mode" = "dark" ]; then
            ${pkgs.jq}/bin/jq 'del(.theme)' "$f" > "$tmp" && mv "$tmp" "$f"
          else
            ${pkgs.jq}/bin/jq --arg t "light" '.theme = $t' "$f" > "$tmp" && mv "$tmp" "$f"
          fi
        fi
      }

      dark() {
        install -m 0644 "$THEMES/dark.conf" "$THEME_CONF"
        echo "dark-mode --dark" > ~/.config/delta/theme 2>/dev/null || true
        echo "prefer-dark" > ~/.config/current-color_scheme 2>/dev/null || true
        { cat "${aerc}/stylesets/dark" > "${aerc}/stylesets/current"; } 2>/dev/null || true
        tmux_theme dark
        claude_theme dark
      }

      light() {
        install -m 0644 "$THEMES/light.conf" "$THEME_CONF"
        echo "light-mode" > ~/.config/delta/theme 2>/dev/null || true
        echo "prefer-light" > ~/.config/current-color_scheme 2>/dev/null || true
        { cat "${aerc}/stylesets/light" > "${aerc}/stylesets/current"; } 2>/dev/null || true
        tmux_theme light
        claude_theme light
      }

      sunlight() {
        install -m 0644 "$THEMES/sunlight.conf" "$THEME_CONF"
        echo "light-mode" > ~/.config/delta/theme 2>/dev/null || true
        echo "prefer-sunlight" > ~/.config/current-color_scheme 2>/dev/null || true
        { cat "${aerc}/stylesets/light" > "${aerc}/stylesets/current"; } 2>/dev/null || true
        tmux_theme sunlight
        claude_theme light
      }

      if [ ! -f ~/.config/delta/theme ]; then
        mkdir -p ~/.config/delta
        touch ~/.config/delta/theme
        light
      fi

      if [ "$color" = "dark" ]; then
        dark
      elif [ "$color" = "light" ]; then
        light
      elif [ "$color" = "sunlight" ]; then
        sunlight
      elif [ -n "$path" ] && [ -f "$path" ]; then
        if grep -q "prefer-dark" "$path"; then
          dark
        elif grep -q "prefer-sunlight" "$path"; then
          sunlight
        else
          light
        fi
      fi

      pkill -SIGUSR1 .kitty-wrapped || pkill -SIGUSR1 kitty || true
    '';
    executable = true;
  };

  # macOS note: nix-built kitty.app has a broken signature (the nix PATH wrapper
  # replaces the signed binary), which is fixed by re-signing in the home-manager
  # activation script in air.nix/work.nix. If that ever stops working on a future
  # macOS, drop the `package` override below and add `kitty` to homebrew.casks.
  programs.kitty = {
    package = kitty;
    enable = true;
    shellIntegration.enableZshIntegration = true;

    extraConfig = ''
      include current-theme.conf
      open_url_with ${url-open}/bin/url-open
      # Allow neovim jump to last cursor position
      map ctrl+shift+o no_op
      map ctrl+shift+n no_op
      map ctrl+shift+p no_op
      # Enable bracketed paste mode for safe multiline pasting
      paste_actions quote-urls-at-prompt
      copy_on_select no
      clipboard_control write-primary write-clipboard read-clipboard no-append
      map shift+insert paste_from_clipboard
      map alt+shift+c copy_to_clipboard
      map alt+shift+v paste_from_clipboard
    '';

    font = {
      name = "FiraCode Nerd Font Mono";
      package = pkgs.nerd-fonts.fira-code;
    };
  };

}
