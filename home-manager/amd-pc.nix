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
    # 26.05 changes the gtk4 theme default to null; keep theming gtk4 like gtk3.
    gtk4.theme = config.gtk.theme;
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
  # interactive terminal from a GUI session. Interactive zsh sets
  # PINENTRY_USER_DATA=curses (see .zshrc_local); everything else -- GUI apps and
  # Claude Code's non-interactive shells, which have no usable terminal driver --
  # falls through to the GNOME prompter.
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

    # Route the YubiKey PIN prompt to this terminal. ssh requests (git fetch over
    # the YubiKey) carry no client env, so gpg-agent uses its startup context --
    # updatestartuptty copies this session's tty and PINENTRY_USER_DATA into it.
    # Guarded on a real tty so non-interactive shells keep the GUI prompter.
    if [[ -o interactive ]] && [[ -t 0 ]]; then
      export GPG_TTY="$TTY"
      export PINENTRY_USER_DATA=curses
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
        output="$(${config.wayland.windowManager.hyprland.package}/bin/hyprctl -j monitors all \
          | ${pkgs.jq}/bin/jq -r '[.[] | .name | select(startswith("HEADLESS-"))][0] // empty')"
        if [ -z "$output" ]; then
          ${config.wayland.windowManager.hyprland.package}/bin/hyprctl output create headless
          output="$(${config.wayland.windowManager.hyprland.package}/bin/hyprctl -j monitors all \
            | ${pkgs.jq}/bin/jq -r '[.[] | .name | select(startswith("HEADLESS-"))][0] // empty')"
        fi

        ${config.wayland.windowManager.hyprland.package}/bin/hyprctl eval \
          "remote_workspace_rule = hl.workspace_rule({ workspace = \"11\", monitor = \"$output\", default = true, persistent = true, layout = \"dwindle\" })"
        ${config.wayland.windowManager.hyprland.package}/bin/hyprctl dispatch \
          'hl.dsp.focus({ workspace = 11 })'

        password="$(< /run/secrets/wayvnc_password)"
        umask 077
        ${pkgs.coreutils}/bin/printf '%s\n' "$output" > "$XDG_RUNTIME_DIR/wayvnc-remote.output"
        ${pkgs.coreutils}/bin/printf '%s\n' \
          'enable_auth=true' \
          "password=$password" \
          'relax_encryption=true' \
          'allow_broken_crypto=true' \
          > "$XDG_RUNTIME_DIR/wayvnc-remote.conf"

        exec ${pkgs.wayvnc}/bin/wayvnc \
          -C "$XDG_RUNTIME_DIR/wayvnc-remote.conf" \
          -f 30 -k pl -o "$output" 127.0.0.1:5900
      '';
      ExecStopPost = pkgs.writeShellScript "wayvnc-remote-cleanup" ''
        ${config.wayland.windowManager.hyprland.package}/bin/hyprctl eval \
          'if remote_workspace_rule then remote_workspace_rule:set_enabled(false); remote_workspace_rule = nil end' \
          || true
        if [ -s "$XDG_RUNTIME_DIR/wayvnc-remote.output" ]; then
          output="$(< "$XDG_RUNTIME_DIR/wayvnc-remote.output")"
          ${config.wayland.windowManager.hyprland.package}/bin/hyprctl output remove "$output" || true
        fi
        ${pkgs.coreutils}/bin/rm -f \
          "$XDG_RUNTIME_DIR/wayvnc-remote.conf" \
          "$XDG_RUNTIME_DIR/wayvnc-remote.output"
      '';
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
