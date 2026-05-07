{ pkgs
, inputs
, lib
, pkgs-unstable
, pkgs-master
, config
, ...
}:
{

  imports = [
  ];

  # Add nix-homebrew configuration
  nix-homebrew = {
    mutableTaps = false;
    enable = true;
    enableRosetta = true;
    user = "flakm";
    autoMigrate = true;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
      "nikitabobko/homebrew-tap" = inputs.homebrew-nikitabobko;
    };
    #mutableTaps = true;
  };

  system.stateVersion = 5;

  environment.systemPackages = with pkgs; [
    bat
    home-manager


    rustup
    podman
    #spotify

    protobuf
    buf
    grpc-gateway

    iconv
    age
    mariadb

    terraform

    # proxy for intercepting traffic
    mitmproxy

    # for scopes service
    pkg-config
    oniguruma
    openssl

  ];



  sops.defaultSopsFile = ../../secrets/secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets = {
    "work_npmrc" = {
      owner = config.users.users.flakm.name;
    };
    "jfrog_env" = {
      owner = config.users.users.flakm.name;
    };
    "github_personal_access_token" = {
      owner = config.users.users.flakm.name;
    };
  };




  fonts.packages = [
    pkgs.nerd-fonts.fira-code
  ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
  };


  users.users.flakm = {
    home = "/Users/flakm";
    shell = pkgs.zsh;
    uid = 501;
  };

  users.knownUsers = [
    "flakm"
  ];




  security.sudo.extraConfig = ''
    flakm ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/darwin-rebuild, /run/current-system/sw/bin/nix*, /run/current-system/sw/bin/launchctl, /usr/bin/env nix*
  '';

  # The previous home-manager generations created a root-owned ~/Applications/Home
  # Manager Apps/ with symlinks into /nix/store. linkApps is now disabled, but the
  # stale directory persists and Launch Services keeps re-registering the store
  # paths from it. Remove it as root on each system activation.
  system.activationScripts.extraActivation.text = ''
    rm -rf "/Users/flakm/Applications/Home Manager Apps"
  '';

  homebrew = {
    enable = true;

    brews = [
      "docker"
    ];

    casks = [
      "aerospace"
    ];
    user = "flakm";

    #mutableTaps = false;
    #onActivation.cleanup = "zap";
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
      ];
    };
  };

}
