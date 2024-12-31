{ pkgs, inputs, lib, pkgs-unstable, pkgs-master, config, ... }:
{

  imports = [
  ];

  # Add nix-homebrew configuration
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = "flakm";
    autoMigrate = true;
  };

  system.stateVersion = 5;

  services.nix-daemon.enable = true;

  environment.systemPackages = with pkgs; [
    bat
    home-manager


    rustup
    podman
    spotify

    protobuf
    iconv
    age
    mariadb
    
    zed-editor
  ];



  sops.defaultSopsFile = ../../secrets/secrets.yaml;
  #  sops.secrets = {
  #    "work_npmrc" = {
  #      path = "${config.users.users.flakm.home}/.npmrc";
  #      mode = "0440";
  #      #owner = config.users.users.flakm.name;
  #      #neededForUsers = true;
  #    };
  #  };




  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" ]; })
  ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
  };

  environment.shells = with pkgs; [
    zsh
    bashInteractive
  ];


  users.users.flakm = {
    home = "/Users/flakm";
    shell = pkgs.zsh;
    uid = 501;
  };

  users.knownUsers = [
    "flakm"
  ];


  environment.pathsToLink = [ "/share/zsh" ];



  services.tailscale.enable = true;


  system.activationScripts.postUserActivation.text = ''
    rsyncArgs="--archive --checksum --chmod=-w --copy-unsafe-links --delete"
    apps_source="${config.system.build.applications}/Applications"
    moniker="Nix Trampolines"
    app_target_base="$HOME/Applications"
    app_target="$app_target_base/$moniker"
    mkdir -p "$app_target"
    # shellcheck disable=SC2086
    ${pkgs.rsync}/bin/rsync $rsyncArgs "$apps_source/" "$app_target"
  '';



  # Add ability to use TouchID for sudo
  #security.pam.enableSudoTouchIdAuth = true;

  homebrew = {
    enable = true;
    casks = [
      "aerospace"
      "anki"
      "docker"
    ];
    taps = [
      "nikitabobko/tap"
    ];
    onActivation.cleanup = "zap";
  };


  # System settings
  system = {
    defaults = {
      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        ApplePressAndHoldEnabled = false;
        AppleShowAllExtensions = true;
        KeyRepeat = 2;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        NSAutomaticWindowAnimationsEnabled = false;
        NSDocumentSaveNewDocumentsToCloud = false;
        NSNavPanelExpandedStateForSaveMode = true;
        PMPrintingExpandedStateForPrint = true;
      };
      LaunchServices = {
        LSQuarantine = false;
      };
      trackpad = {
        TrackpadRightClick = true;
        TrackpadThreeFingerDrag = true;
        Clicking = true;
      };
      finder = {
        AppleShowAllFiles = true;
        CreateDesktop = false;
        FXDefaultSearchScope = "SCcf";
        FXEnableExtensionChangeWarning = false;
        FXPreferredViewStyle = "Nlsv";
        QuitMenuItem = true;
        ShowPathbar = true;
        ShowStatusBar = true;
        _FXShowPosixPathInTitle = true;
        _FXSortFoldersFirst = true;
      };
      dock = {
        autohide = true;
        expose-animation-duration = 0.15;
        show-recents = false;
        showhidden = true;
        persistent-apps = [
          #"/Applications/Brave Browser.app"
          #"${pkgs.alacritty}/Applications/Alacritty.app"
          #"${pkgs.telegram-desktop}/Applications/Telegram.app"
        ];
        tilesize = 30;
        wvous-bl-corner = 1;
        wvous-br-corner = 1;
        wvous-tl-corner = 1;
        wvous-tr-corner = 1;
      };
      screencapture = {
        location = "/Users/flakm/Downloads/temp";
        type = "png";
        disable-shadow = true;
      };
    };
    keyboard = {
      enableKeyMapping = true;
      # swapLeftCtrlAndFn = true;
      # Remap §± to ~
      userKeyMapping = [
        {
          HIDKeyboardModifierMappingDst = 30064771125;
          HIDKeyboardModifierMappingSrc = 30064771172;
        }

        #{
        #  HIDKeyboardModifierMappingSrc = 30064771296; # left control
        #  HIDKeyboardModifierMappingDst = 30064771299; # left command
        #}
        #{
        #  HIDKeyboardModifierMappingSrc = 30064771299; # left command
        #  HIDKeyboardModifierMappingDst = 30064771296; # left control
        #}
      ];
    };
  };




}

