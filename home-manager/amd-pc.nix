{ config, lib, pkgs, ... }:

{
  # Ensure cargo and go tools are in the PATH
  home.sessionPath = [
    "${config.home.homeDirectory}/.cargo/bin"
    "${config.home.homeDirectory}/go/bin"
    "/usr/local/bin"
  ];

  imports = [
    ./modules/home-manager.nix
    ./modules/common.nix
    ./modules/nvim/neovim.nix
    ./modules/rust.nix
    ./modules/tmux.nix
    ./modules/git.nix
    ./modules/gpg_home.nix
    ./modules/brother.nix

    ./modules/yubikey.nix


    ./modules/communication.nix

    ./modules/sql.nix

    ./modules/firefox.nix
    ./modules/productivity.nix
    ./modules/media.nix

    ./modules/hyprland.nix
    ./modules/quickshell.nix
    #./modules/neomutt.nix

    ./modules/atuin.nix
    ./modules/kitty.nix
    ./modules/starship.nix
    ./modules/zsh.nix

    #./modules/zellij.nix
    ./modules/jira_cli.nix

    ./modules/scala.nix

    ./modules/aws.nix

    ./modules/ai.nix
    ./modules/vikunja.nix

    ./modules/k8s.nix
    ./modules/front.nix
    ./modules/calendar.nix
    ./modules/mermaid
    ./modules/peon-ping.nix
    ./modules/pw-play-wrapper.nix
    ./modules/eink-bridge.nix
    ./modules/omada.nix
  ];

  xdg.enable = true;

  dconf.settings."org/blueman/plugins/autoconnect".services = [ ];



  wayland.windowManager.hyprland.settings = {
    # Monitor settings
    monitor = [ "DP-1,5120x1440@144,0x0,1.0" ];
    master = {
      orientation = "center";
      slave_count_for_center_master = 0;
      mfact = 0.55;
    };

    general = {
      layout = "master";
    };
  };

  gtk = {
    enable = true;
    theme = {
      package = pkgs.gnome-themes-extra;
      name = "Adwaita-dark";
    };
    iconTheme = {
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.theme = null;
    font = {
      name = "FiraCode";
      size = 11;
    };
  };

  home = {
    username = "flakm";
    homeDirectory = "/home/flakm";
    pointerCursor = {
      gtk.enable = true;
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Amber";
      size = 48;
    };
    stateVersion = "23.05";


  };

  # ~/.gnupg/gpg-agent.conf
  # pinentry-auto: PINENTRY_USER_DATA is the only signal gpg-agent forwards per
  # request. DISPLAY/WAYLAND_DISPLAY leak in from the gpg-agent systemd user
  # service env (so they are always set, regardless of the calling shell), and
  # stdin is always an Assuan pipe, never a tty -- so neither can distinguish an
  # interactive terminal from a GUI session. Only interactive zsh inside an SSH
  # session sets PINENTRY_USER_DATA=curses (see .zshrc_local); everything else --
  # local terminals, GUI apps and non-interactive shells -- gets the GNOME
  # prompter.
  xdg.configFile."/.gnupg/gpg-agent.conf".text =
    let
      pinentry-auto = pkgs.writeShellScript "pinentry-auto" ''
        case "$PINENTRY_USER_DATA" in
          *curses*) exec ${pkgs.pinentry-curses}/bin/pinentry-curses "$@" ;;
        esac
        exec ${pkgs.pinentry-gnome3}/bin/pinentry-gnome3 "$@"
      '';
    in
    ''
      enable-ssh-support
      write-env-file
      use-standard-socket
      default-cache-ttl 600
      max-cache-ttl 7200
      pinentry-program ${pinentry-auto}
    '';

  home.file.".zshrc_local".text = ''
    # Ensure SSH uses gpg-agent socket (YubiKey)
    export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"

    # ssh requests (git fetch over the YubiKey) carry no client env, so gpg-agent
    # uses its startup context -- updatestartuptty copies this session's tty and
    # PINENTRY_USER_DATA into it. Only fall back to the curses prompter when
    # there is no local display to draw on (i.e. we are inside an SSH session).
    if [[ -o interactive ]] && [[ -t 0 ]]; then
      export GPG_TTY="$TTY"
      if [[ -n "$SSH_CONNECTION$SSH_TTY$SSH_CLIENT" ]]; then
        export PINENTRY_USER_DATA=curses
      else
        unset PINENTRY_USER_DATA
      fi
      gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
    fi
  '';


  home.packages = with pkgs; [
    pritunl-client
    qmk
    qmk_hid
    wayvnc
  ];

  systemd.user.services.wayvnc-remote = {
    Unit = {
      Description = "WayVNC remote desktop";
      PartOf = [ "wayland-session@Hyprland.target" ];
      After = [ "wayland-session@Hyprland.target" ];
      ConditionPathExists = "/run/secrets/wayvnc_password";
    };
    Service = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "wayvnc-remote" ''
        set -euo pipefail
        hyprctl=${config.wayland.windowManager.hyprland.package}/bin/hyprctl
        state_dir="$XDG_RUNTIME_DIR/wayvnc-remote"
        output="REMOTE-1"
        ${pkgs.coreutils}/bin/mkdir -p "$state_dir"

        primary="$($hyprctl -j monitors \
          | ${pkgs.jq}/bin/jq -r '[.[] | select(.focused).name][0] // empty')"
        ${pkgs.coreutils}/bin/printf '%s\n' "$output" > "$state_dir/output"
        ${pkgs.coreutils}/bin/printf '%s\n' "$primary" > "$state_dir/primary"

        if ! $hyprctl -j monitors all \
          | ${pkgs.jq}/bin/jq -e --arg output "$output" \
            '.[] | select(.name == $output)' >/dev/null; then
          $hyprctl output create headless "$output"
        fi

        mode=""
        for _ in $(${pkgs.coreutils}/bin/seq 1 50); do
          mode="$($hyprctl -j monitors all \
            | ${pkgs.jq}/bin/jq -r --arg output "$output" \
              '.[] | select(.name == $output) | "\(.width)x\(.height)@\(.scale)"')"
          [ "$mode" = "3456x2234@2" ] && break
          ${pkgs.coreutils}/bin/sleep 0.1
        done
        [ "$mode" = "3456x2234@2" ]

        active_workspace="$($hyprctl -j monitors \
          | ${pkgs.jq}/bin/jq -r --arg primary "$primary" \
            '.[] | select(.name == $primary) | .activeWorkspace.id')"
        workspaces="$($hyprctl -j workspaces \
          | ${pkgs.jq}/bin/jq -r --arg primary "$primary" \
            '.[] | select(.monitor == $primary) | .id')"
        for workspace in $workspaces; do
          $hyprctl eval \
            "hl.dispatch(hl.dsp.workspace.move({ workspace = $workspace, monitor = \"$output\" }))"
        done
        $hyprctl eval \
          "hl.dispatch(hl.dsp.focus({ monitor = \"$output\" }))"
        if [ -n "$active_workspace" ]; then
          $hyprctl eval \
            "hl.dispatch(hl.dsp.focus({ workspace = $active_workspace }))"
        fi
        password="$(< /run/secrets/wayvnc_password)"
        umask 077
        ${pkgs.coreutils}/bin/printf '%s\n' \
          'enable_auth=true' \
          "password=$password" \
          'relax_encryption=true' \
          'allow_broken_crypto=true' \
          > "$state_dir/config"

        exec ${pkgs.wayvnc}/bin/wayvnc \
          -C "$state_dir/config" \
          -e -f 60 -g -r -R -k pl -o "$output" 127.0.0.1:5900
      '';
      ExecStopPost = pkgs.writeShellScript "wayvnc-remote-cleanup" ''
        state_dir="$XDG_RUNTIME_DIR/wayvnc-remote"
        if [ -s "$state_dir/output" ]; then
          output="$(< "$state_dir/output")"
          primary="$(< "$state_dir/primary")"
          if [ -n "$primary" ]; then
            workspaces="$(${config.wayland.windowManager.hyprland.package}/bin/hyprctl \
              -j workspaces \
              | ${pkgs.jq}/bin/jq -r --arg output "$output" \
                '.[] | select(.monitor == $output) | .id')"
            for workspace in $workspaces; do
              ${config.wayland.windowManager.hyprland.package}/bin/hyprctl eval \
                "hl.dispatch(hl.dsp.workspace.move({ workspace = $workspace, monitor = \"$primary\" }))" \
                || true
            done
            ${config.wayland.windowManager.hyprland.package}/bin/hyprctl eval \
              "hl.dispatch(hl.dsp.focus({ monitor = \"$primary\" }))" || true
          fi
          ${config.wayland.windowManager.hyprland.package}/bin/hyprctl output \
            remove "$output" || true
        fi
        ${pkgs.coreutils}/bin/rm -rf "$state_dir"
      '';
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  # hyprwhspr-rs voice dictation (service enabled in hosts/amd-pc/configuration.nix).
  # Trigger is the app's built-in global shortcut SUPER+ALT+R (needs the "input"
  # group, already granted). whisper-cpp runs on CPU; model is fetched by Nix.
  xdg.dataFile."hyprwhspr-rs/models/ggml-base.en.bin".source = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin";
    hash = "sha256-oDd5yG3zMjB19eeWyyzlAp8A7Ihp7uP9+4l6/jbG0AI=";
  };

  xdg.configFile."hyprwhspr-rs/config.jsonc".text = ''
    {
      // base.en resolves to ggml-base.en.bin in the default models dir above.
      // Bump to "small.en" (and add that model) if accuracy needs it.
      "transcription": {
        "provider": "whisper_cpp",
        "whisper_cpp": {
          "model": "base.en"
        }
      }
    }
  '';


  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ../secrets/secrets.yaml;

    secrets = {
      "work_npmrc" = {
        path = "${config.home.homeDirectory}/.npmrc";
      };

      "dbs" = {
        sopsFile = ../secrets/dbs.yaml;
        path = "${config.home.homeDirectory}/.dbs.lua";
      };

      "jfrog_env" = {
        path = "${config.home.homeDirectory}/.jfrog.env";
      };

      "neomutt_flakm" = {
        path = "${config.home.homeDirectory}/.neomutt_flakm";
      };

      "neomutt_gmail" = {
        path = "${config.home.homeDirectory}/.neomutt_gmail";
      };
      "google_oauth_client_id" = {
        path = "${config.home.homeDirectory}/.google_oauth_client_id";
      };
      "google_oauth_client_secret" = {
        path = "${config.home.homeDirectory}/.google_oauth_client_secret";
      };
      "mealie_token" = {
        path = "${config.home.homeDirectory}/.mealie_token";
      };
    };
  };



}
