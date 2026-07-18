# configuration in this file only applies to amd-pc host.

{ pkgs, inputs, lib, pkgs-unstable, pkgs-master, config, ... }:

let
  fenix = inputs.fenix.packages.${pkgs.stdenv.hostPlatform.system}.stable;
  hasHermesSlackSecret = lib.hasInfix "hermes_slack_bot_token:" (builtins.readFile ../../secrets/secrets.yaml);

  # Workaround for upstream Hyprland regression (2026-05-06, rev 78b8ce22):
  # example/hyprland.conf was removed but CMakeLists.txt still installs it.
  # Drop this override once upstream fixes either the install rule or the file.
  hyprland-pkgs = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
  hyprland-fixed = hyprland-pkgs.hyprland.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      touch example/hyprland.conf
    '';
  });
  xdph-fixed = hyprland-pkgs.xdg-desktop-portal-hyprland.override {
    hyprland = hyprland-fixed;
  };
  # UWSM derives the compositor ID (and XDG_CURRENT_DESKTOP) from the binPath
  # basename. We want both start-hyprland (for the watchdog fd) and
  # XDG_CURRENT_DESKTOP=Hyprland (so xdg-desktop-portal loads the hyprland
  # backend — without it, hyprland-portals.conf and hyprland.portal UseIn don't
  # match, ScreenCast/Screenshot disappear, and screen-share pickers break).
  hyprland-start = pkgs.writeShellScriptBin "Hyprland" ''
    exec ${hyprland-fixed}/bin/start-hyprland --path ${hyprland-fixed}/bin/Hyprland "$@"
  '';
in

{
  imports = [
    ../../shared/wireguard.nix
    ../../shared/gpg.nix
    #../../shared/k3s/server.nix
    ../../shared/syncthing/amd-pc.nix
    ./zfs_replication.nix
    ./postgres.nix
    ./grafana.nix
    ./performance.nix
    ./vpn.nix
    #./clickhouse.nix
    ./microvm.nix
  ];

  # Elephant backend for the walker launcher (user service).
  services.elephant.enable = true;

  # Voice dictation for Hyprland (user service). Local whisper-cpp on CPU;
  # keybinds + model live in home-manager/amd-pc.nix.
  services.hyprwhspr-rs.enable = true;

  services.hermes-agent = {
    enable = true;
    package = inputs.coralogix-private.packages.${pkgs.stdenv.hostPlatform.system}.hermes-agent;
    user = "flakm";
    group = "users";
    createUser = false;
    stateDir = "/var/lib/hermes-agent";
    environment = {
      CODEX_HOME = "/home/flakm/.codex";
      CX_READ_ONLY = "1";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
      HOME = "/home/flakm";
      XDG_RUNTIME_DIR = "/run/user/1000";
    } // lib.optionalAttrs hasHermesSlackSecret {
      SLACK_BOT_TOKEN_FILE = config.sops.secrets.hermes_slack_bot_token.path;
    };
    path = [
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
      inputs.cx-cli.packages.${pkgs.stdenv.hostPlatform.system}.default
      pkgs.libnotify
      pkgs-master.signal-cli
    ];
    settings = {
      agent = {
        name = "hermes";
        provider = "codex";
        model = "gpt-5.5";
        decisionPolicy = builtins.readFile ./hermes-interest.md;
        ignoredAuthorUserIds = [
          "self"
          "U082RB1R9U4" # flakm
        ];
        ignoredAuthorUserIdsByChannel = {
          "C0BBE5L48AU" = [ ]; # flakm-test
        };
        importantMentions = [
          "<@U082RB1R9U4>"
          "rnd-vertex-aaa"
        ];
        interestKeywords = [ ];
        memoryDir = "/home/flakm/.local/share/hermes-agent/memory";
        memoryMaxChars = 6000;
        workingDirectory = "/home/flakm/programming/coralogix/aaa-daily-reporter";
        contextPaths = [
          "/home/flakm/programming/coralogix/aaa-daily-reporter"
          "/home/flakm/programming/coralogix/cx-cli"
          "${inputs.cx-cli.packages.${pkgs.stdenv.hostPlatform.system}.skills}"
        ];
        contextInstructions = ''
          Use aaa-daily-reporter as Maciej's AAA operational map: service inventory, known-noise context, custom checks, login-events privacy rules, auditor lag checks, blocked-team checks, and daily health-report semantics.

          Use cx-cli as the read-only observability tool. The `cx` binary is on PATH. Prefer `cx schema` for command discovery and the skills under cx-cli/skills for query workflows. Read-only commands such as `cx logs`, `cx spans`, `cx metrics`, `cx search-fields`, `cx alerts list/get/events`, `cx incidents list/get`, and `cx iam ... list/get/search` are allowed when a Slack thread looks investigation-worthy.

          Never run cx write/risky operations. Never pass `--yes`. Keep any live telemetry query narrow: recent time windows, low limits, and `-o agents` or `-o json`. Do not query telemetry for routine PR links, greetings, or already-clear Slack threads; use the repos/skills mostly as background unless the thread mentions incidents, SSO/login/authz/permissions failures, customer impact, production/staging errors, audit-log delivery, blocked teams, Kafka lag, or requests for investigation.

          When using AAA reporter checks, follow their privacy rules. In particular, login-events checks must not inspect actor/client fields and should aggregate by safe dimensions only.
        '';
      };
      slack = {
        watchedChannels = [
          "C03K13XKV6G" # internal
          "C03KNEM5DCG" # interface
          "C0BBE5L48AU" # flakm-test
        ];
        pollIntervalSeconds = 30;
        maxDecisionsPerChannelPerPoll = 5;
        requireThreadParticipation = false;
        backfillOnStart = false;
        threadLookback = "2d";
      };
      escalation = {
        urgentChannels = [ ];
        desktopNotifications = false;
        signal = {
          enable = true;
          account = "+48786816597";
          configDir = "/home/flakm/.local/share/signal-cli-hermes";
          noteToSelf = true;
          recipients = [ ];
        };
        includeCollectedContext = false;
      };
    };
  };

  # Root dataset still needs a fileSystems entry even when we rely on ZFS
  # mountpoint properties for everything else.
  fileSystems."/" = {
    device = "rpool/nixos/root";
    fsType = "zfs";
    options = [ "zfsutil" "X-mount.mkdir" "noatime" ];
    neededForBoot = true;
  };

  # /boot must be on the unencrypted bpool (GRUB cannot read encrypted rpool).
  # Required because zfs-root.fileSystems.generateDataMounts = false skips
  # auto-generated entries and bpool/nixos/root has mountpoint=legacy.
  # No zfsutil: that option is for non-legacy mountpoints; with mountpoint=legacy
  # mount.zfs refuses with "cannot be mounted using 'zfs mount'". neededForBoot
  # is also not set — /boot only needs to be available in stage 2 (for
  # bootloader install), and pulling bpool into initrd is unnecessary churn.
  fileSystems."/boot" = {
    device = "bpool/nixos/root";
    fsType = "zfs";
    options = [ "X-mount.mkdir" "noatime" ];
  };

  nix.package = pkgs.nixVersions.latest;

  # Import the boot pool so /boot is mounted from bpool (GRUB-compatible).
  boot.zfs.extraPools = [ "bpool" ];

  systemd.services.zfs-mount.enable = true;

  services.ollama = {
    enable = true;
    # CPU-only inference. GPU acceleration was investigated exhaustively:
    #   - Vulkan (ollama-vulkan): blocked — ggml needs a single 6.9GB buffer but
    #     Vulkan maxStorageBufferRange is uint32_t-limited to 4GB (spec constraint).
    #   - ROCm (ollama-rocm, gfx1036→gfx1030 override): works but 8-10× slower than
    #     CPU because the Raphael iGPU shares DDR5 bandwidth with the CPU (UMA), and
    #     AVX-512 Zen4 wins this memory-bandwidth-bound workload.
    # CPU with qwen2.5vl:7b takes 3–33 s per annotation group, which is acceptable.
    package = pkgs-unstable.ollama;
    environmentVariables = {
      OLLAMA_NUM_PARALLEL = "1";
      # OCR outputs are short; 1024 tokens is ample and keeps KV cache small.
      OLLAMA_CONTEXT_LENGTH = "1024";
    };
  };

  # Pull OCR models on first boot. glm-ocr is the primary (2× faster than qwen2.5vl:7b
  # for typical short annotations). qwen2.5vl:7b is the fallback for long cursive text
  # (set EINK_OLLAMA_MODEL=qwen2.5vl:7b to use it).
  systemd.services.ollama-pull-qwen = {
    description = "Pull OCR models for eink-bridge";
    after = [ "ollama.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    requires = [ "ollama.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'until ${pkgs.curl}/bin/curl -sf http://127.0.0.1:11434/api/tags >/dev/null; do sleep 1; done'";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs-unstable.ollama}/bin/ollama pull glm-ocr && ${pkgs-unstable.ollama}/bin/ollama pull qwen2.5vl:7b'";
    };
    environment = {
      OLLAMA_HOST = "127.0.0.1:11434";
      OLLAMA_MODELS = "/var/lib/ollama/models";
      HOME = "/var/lib/ollama";
    };
  };

  networking.extraHosts =
    ''
      127.0.0.1 modivo.local
      fdf3:e1c5:2572::f:9:1 eobuwie-db.local

      # cx.test — local-dev parent domain (RFC 6761 reserved-for-testing TLD)
      # so SSO cookies set with domain=cx.test are sent to all team
      # subdomains, mirroring the *.coralogix.com cookie sharing in
      # staging/prod. Avoids `.localhost`'s special browser handling.
      127.0.0.1 sso.cx.test
      127.0.0.1 dashboard.cx.test
      127.0.0.1 aaa-multisaml-testing.cx.test
      127.0.0.1 aaa-multisaml-testing-org1.cx.test
      127.0.0.1 aaa-multisaml-testing-org2.cx.test
    '';


  #boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  #boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;
  programs.hyprland = {
    enable = true;
    package = hyprland-fixed;
    portalPackage = xdph-fixed;
    systemd.setPath.enable = true;
    withUWSM = true;
  };

  # Use a wrapper named "Hyprland" (not "start-hyprland") so UWSM's compositor
  # ID — and the resulting XDG_CURRENT_DESKTOP — stay "Hyprland". The wrapper
  # still execs start-hyprland for the watchdog fd. See hyprland-start above.
  programs.uwsm.waylandCompositors.hyprland = {
    prettyName = "Hyprland";
    binPath = lib.mkForce "${hyprland-start}/bin/Hyprland";
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [
      xdph-fixed
      pkgs.xdg-desktop-portal-gtk
    ];
    configPackages = [
      pkgs.xdg-desktop-portal-gtk
      xdph-fixed
    ];
  };

  services.redis.servers."".enable = false;


  # networking.hostName = "nixos"; # Define your hostname.
  networking.networkmanager.enable = lib.mkForce false;

  networking.hostName = "amd-pc";

  time.timeZone = "Europe/Warsaw";

  # Sops secrets configuration
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ../../secrets/secrets.yaml;
  sops.secrets = {
    coralogix_blog_send_key = {
      path = "/var/secrets/coralogix_send_key";
      mode = "0440";
      owner = "flakm";
      group = "users";
    };
    samba_flakm_password = {
      mode = "0440";
      owner = "flakm";
      group = "users";
      restartUnits = [ "create-samba-credentials.service" ];
    };
  } // lib.optionalAttrs hasHermesSlackSecret {
    hermes_slack_bot_token = {
      owner = "flakm";
      group = "users";
      mode = "0400";
      restartUnits = [ "hermes-agent.service" ];
    };
  };

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  #networking.useDHCP = false;
  #networking.interfaces.enp14s0.useDHCP = false;
  #networking.interfaces.eth0.useDHCP = true;

  programs.dconf = {
    enable = true;
    profiles.gdm.databases = [{
      settings = {
        "org/gnome/desktop/background" = {
          picture-uri = "file://${inputs.self}/wallpapers/wallpaper.png";
          picture-uri-dark = "file://${inputs.self}/wallpapers/wallpaper.png";
          picture-options = "zoom";
        };
        "org/gnome/desktop/screensaver" = {
          picture-uri = "file://${inputs.self}/wallpapers/wallpaper.png";
          picture-options = "zoom";
        };
      };
    }];
  };
  programs.thunar = {
    enable = true;
    plugins = [ pkgs.thunar-volman ];
  };
  programs.xfconf.enable = true;

  # nix-ld lets dynamically-linked binaries from non-Nix sources run
  # (e.g. fnm-installed Node, prebuilt vendor toolchains).
  programs.nix-ld.enable = true;

  security.rtkit.enable = true;
  security.sudo.extraConfig = "Defaults env_keep += \"SSH_AUTH_SOCK\"";
  security.pam.services.hyprlock = { }; # allow hyprlock to authenticate

  services.blueman.enable = true;

  services.pulseaudio.enable = false;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    audio.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
    jack.enable = true;

    # Configure default HDMI audio for LG monitor
    wireplumber.configPackages = [
      (pkgs.writeTextDir "share/wireplumber/main.lua.d/51-hdmi-audio.lua" ''
        -- Force HDMI card profile to be active
        rule = {
          matches = {
            {
              { "device.name", "equals", "alsa_card.pci-0000_18_00.1" },
            },
          },
          apply_properties = {
            ["device.profile"] = "output:hdmi-stereo-extra2",
            ["api.acp.auto-profile"] = "false",
          },
        }
        table.insert(alsa_monitor.rules, rule)

        -- Set HDMI as default sink with high priority
        default_sink_rule = {
          matches = {
            {
              { "node.name", "equals", "alsa_output.pci-0000_18_00.1.hdmi-stereo-extra2" },
            },
          },
          apply_properties = {
            ["node.priority.driver"] = 2000,
            ["node.priority.session"] = 2000,
          },
        }
        table.insert(alsa_monitor.rules, default_sink_rule)
      '')
    ];
  };

  services.libinput.enable = true;

  # Login greeter: greetd + ReGreet (GTK on cage). Replaces GDM, which on
  # GNOME/GDM 50 black-screens without a full GNOME install (nixpkgs#523332).
  # ReGreet only discovers sessions via XDG_DATA_DIRS, and NixOS doesn't expose
  # /run/current-system/sw/share/wayland-sessions, so point the greeter at the
  # display-manager session bundle (which holds the Hyprland (UWSM) entry).
  programs.regreet = {
    enable = true;
    theme.name = "Adwaita-dark";
    extraCss = ''
      window,
      window > box {
        background-color: #000000;
      }
    '';
  };
  services.greetd.settings.default_session.command = lib.mkForce (
    "${pkgs.dbus}/bin/dbus-run-session ${lib.getExe pkgs.cage} -s -d -- "
    + "${pkgs.coreutils}/bin/env "
    + "XDG_DATA_DIRS=${config.services.displayManager.sessionData.desktops}/share "
    + "${lib.getExe config.programs.regreet.package}"
  );


  services.xserver = {
    enable = false; # might need it for xwayland
    xkb.layout = "pl";
    xkb.options = "altwin:ctrl_win";
  };



  # Configure keymap in X11
  #services.xserver.layout = "pl";
  # services.xserver.xkb.options = "eurosign:e";
  i18n.defaultLocale = "en_US.UTF-8";


  services.fwupd.enable = true;
  services.dbus.enable = true;


  hardware = {
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        mesa
        libva
        libva-utils
      ];
      extraPackages32 = with pkgs.pkgsi686Linux; [
        mesa
        libva
      ];
    };
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General.Experimental = true;
        Policy.ReconnectAttempts = 0;
      };
    };
    # MediaTek MT7922 Bluetooth controller (0e8d:0616) requires firmware from linux-firmware
    # Without this, the controller fails with "wmt command timed out" and "Failed to send wmt patch dwnld"
    firmware = [ pkgs.linux-firmware ];
  };

  # MediaTek MT7922 Bluetooth needs rfkill unblock before bluez can power it on.
  systemd.services.bluetooth-rfkill-unblock = {
    description = "Unblock Bluetooth rfkill";
    wantedBy = [ "bluetooth.service" ];
    before = [ "bluetooth.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.util-linux}/bin/rfkill unblock bluetooth";
    };
  };

  virtualisation.podman = {
    enable = false;
    #   defaultNetwork.settings.dns_enabled = true;
  };

  virtualisation.docker = {
    enable = true;
    #storageDriver = "zfs";
    daemon.settings = {
      log-driver = "json-file";
      log-opts = {
        max-size = "10m";
        max-file = "3";
      };
      #bip = "172.26.0.1/16";
      #default-address-pools = [
      #  {
      #    base = "172.26.0.1/16";
      #    size = 24;
      #  }
      #];
      #storage-driver = "zfs";
      #storage-opts = [
      #  "zfs.fsname=rpool/docker-optimized"
      #];
      #default-ulimits = {
      #  nofile = {
      #    Name = "nofile";
      #    Soft = 1000000;
      #    Hard = 1000000;
      #  };
      #};
    };
  };

  # enable the tailscale daemon; this will do a variety of tasks:
  # 1. create the TUN network device
  # 2. setup some IP routes to route through the TUN
  services.tailscale = {
    enable = true;
    package = pkgs-unstable.tailscale;
    openFirewall = true;
    extraSetFlags = [ "--ssh=true" ];
  };

  boot.kernelModules = [ "i2c-dev" ];

  users.groups.plugdev = { };


  services.flatpak.enable = true;

  users.users.flakm.openssh.authorizedKeys.keys = lib.mkAfter [
    # temporary keys for pikvm and odroid if the tailscale is not working on amd
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINJ/re3ma3iPQIXyixzDjaQ7Jf7+M/byFMoCHmH9I3pj root@pikvm"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDVvK18r4EdYJOW8Ml9Dp0y0TDqnVaTQswA8AdNmHyde flakm@odroid"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBCSh4nXWO827OwprBKa63SzLnGBqzbG0h6/H9gtjn17 odroid-ccusage-push"
  ];

  environment.pathsToLink = [ "/share/zsh" ];

  security.polkit.enable = true;

  security.pam.services.swaylock = {
    text = "auth include login";
  };


  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    nix-index
    amdgpu_top
    dfu-util
    xkeyboard-config

    qemu_full
    virt-manager
    quickemu
    glib
    linuxHeaders

    xfce4-pulseaudio-plugin
    cifs-utils # For mounting Samba shares

    adwaita-icon-theme
    gnome-themes-extra
    gsettings-desktop-schemas
    gruvbox-dark-gtk

    pavucontrol
    docker
    curl
    xdg-utils

    binutils
    inotify-tools
    lm_sensors

    # vpn/rdp
    jq
    openconnect
    freerdp
    openvpn


    # media
    gimp
    vlc
    simple-scan

    # office
    pkgs-unstable.thunderbird
    gpgme
    libreoffice


    bitwarden-desktop
    bitwarden-cli

    # spelling
    aspell
    aspellDicts.pl
    aspellDicts.en
    aspellDicts.en-computers
    hunspell
    hunspellDicts.en_US-large
    hunspellDicts.pl_PL
    hyphen
    languagetool

    libsForQt5.qtstyleplugins
    adwaita-qt
    adwaita-qt6

    qt5.qtwayland
    qt6.qmake
    qt6.qtwayland


    wgnord

    glibc
    libuuid

    lxqt.lxqt-policykit

    # fun
    spotify


    # network monitoring
    iftop


    #rustup
    #(fenix.withComponents [
    #  "cargo"
    #  "clippy"
    #  "rust-src"
    #  "rustc"
    #  "rustfmt"
    #  "rust-analyzer"
    #])

    #(fenix.packages.targets.thumbv6m-unknown-unknown.withComponents [
    #  "rust-src"
    #  "rustc"
    #])


    #fenix.rust-analyzer

    calibre

    nextcloud-client
    libation

    mariadb

    flatpak

    ddcutil

    bpftune

  ];


  boot.extraModulePackages = [ pkgs.bcc ];

  programs.wireshark = {
    enable = true;
    package = pkgs-unstable.wireshark;
  };

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings = {
      StreamLocalBindUnlink = "yes";
    };
  };

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 8096 8000 3333 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;


  # Depending on the details of your configuration, this section might be necessary or not;
  # feel free to experiment
  #services.pcscd.enable = true;
  #environment.shellInit = ''
  #  export GPG_TTY="$(tty)"
  #  gpg-connect-agent /bye
  #  export SSH_AUTH_SOCK="/run/user/$UID/gnupg/S.gpg-agent.ssh"
  #'';

  # Picks the printer automatically when connected to the network
  # I had to change the driver though to:
  # Brother DCP-B7500D series, using Owl-Maintain/brlaser v6.2.7 (grayscale, 2-sided printing)
  services.printing = {
    enable = true;
    drivers = [ pkgs.brlaser ];
  };

  # Avahi for network printer discovery
  # mDNS/DNS-SD protocols (Multicast DNS / DNS Service Discovery),
  services.avahi = {
    enable = true;
    nssmdns4 = false; # systemd-resolved handles mDNS; nss-mdns4 short-circuits single-label names like 'work'
    openFirewall = true;
  };

  # SANE scanner support
  # Programs like 'simple-scan' will pick up the scanner automatically
  hardware.sane = {
    enable = true;
    brscan4 = {
      enable = true;
      netDevices = {
        "DCP-B7520DW" = {
          model = "DCP-B7520DW";
          ip = "192.168.0.170";
        };
      };
    };
  };

  programs = {

    gnupg = {
      dirmngr.enable = true;
      agent = {
        enableSSHSupport = true;
        pinentryPackage = pkgs.pinentry-tty;
      };
    };
    kdeconnect.enable = true;
  };
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.12"; # Did you read the comment?



  fonts.fontDir.enable = true;
  fonts.packages = [
    pkgs.nerd-fonts.fira-code
  ];


  services.minio = {
    enable = true;
    region = "us-east-1";
  };



  # workaround for openforify client
  environment.etc."ppp/options".text = "ipcp-accept-remote";

  # enable browsing samba shares
  services.gvfs = {
    enable = true;
    package = lib.mkForce pkgs.gnome.gvfs;
  };

  # Create i2c group for secure access
  users.groups.i2c = { };

  services.udev.extraRules = ''
    KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
    # MediaTek MT7922 BT (0e8d:0616): firmware upload times out when USB autosuspend kicks in
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0e8d", ATTRS{idProduct}=="0616", ATTR{power/control}="on"
    # AMD 1022:43f7 xHCI controllers (one hosts the MT7922 BT): runtime D3 resume
    # hits a Save/Restore Error ("xHC error in resume, USBSTS 0x401") that wedges
    # the BT chip until a cold boot. Keep them powered so they never suspend.
    SUBSYSTEM=="pci", ATTR{vendor}=="0x1022", ATTR{device}=="0x43f7", ATTR{power/control}="on"
  '';

  # Add user to i2c group
  users.users.flakm.extraGroups = lib.mkAfter [
    "wheel"
    "docker"
    "audio"
    "input"
    "video"
    "users"
    "dip"
    "bluetooth"
    "plugdev"
    "dialout"
    "scanner"
    "lp"
    "i2c"
  ];

  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "69-probe-rs.rules";
      text = builtins.readFile ./69-probe-rs.rules;
      destination = "/etc/udev/rules.d/69-probe-rs.rules";
    })
    pkgs.qmk-udev-rules
  ];


  # enable gnome keyring for nextcloud-client to store the password
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.gdm.enableGnomeKeyring = true;

  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
  };

  services.bpftune.enable = true;

  # Paperless consume directory mount
  fileSystems."/mnt/paperless-consume" = {
    device = "//192.168.0.102/paperless-consume";
    fsType = "cifs";
    options = [
      "credentials=/var/secrets/samba-credentials"
      "uid=1000"
      "gid=100"
      "file_mode=0664"
      "dir_mode=0775"
      "noauto"
      "user"
      "x-systemd.automount"
      "x-systemd.mount-timeout=10"
      "x-systemd.idle-timeout=60"
    ];
  };

  # Create credentials file from SOPS secret
  systemd.services.create-samba-credentials = {
    description = "Create Samba credentials file from SOPS secret";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
      ExecStart = pkgs.writeShellScript "create-samba-credentials" ''
                set -e
                mkdir -p /var/secrets
        
                if [ -f "${config.sops.secrets.samba_flakm_password.path}" ]; then
                  cat > /var/secrets/samba-credentials << EOF
        username=flakm
        password=$(cat "${config.sops.secrets.samba_flakm_password.path}")
        domain=WORKGROUP
        EOF
                  chmod 600 /var/secrets/samba-credentials
                  echo "Samba credentials file created from SOPS secret"
                else
                  echo "SOPS secret file not found: ${config.sops.secrets.samba_flakm_password.path}"
                  exit 1
                fi
      '';
    };
  };

}
