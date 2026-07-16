{
  description = "Macieks's system config";

  inputs = {
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    # Optional: Declarative tap management
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
    homebrew-nikitabobko = {
      url = "github:nikitabobko/homebrew-tap";
      flake = false;
    };

    # Only needed for odroid builds
    librus-notifications = {
      url = "github:FlakM/czujka-librus";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jump = {
      url = "github:FlakM/jump";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents.url = "github:numtide/llm-agents.nix";

    peon-ping = {
      url = "github:PeonPing/peon-ping";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    eink-bridge = {
      url = "path:/home/flakm/programming/flakm/eink-bridge";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-openclaw.url = "github:openclaw/nix-openclaw";

    cx-cli.url = "github:coralogix/cx-cli";

    coralogix-private = {
      url = "git+ssh://git@github.com/FlakM/nix-coralogix-private";
      # Don't override nixpkgs: aaa-help's deps (cx_* common-rs crates) need
      # rustc 1.92+, which 25.11 stable doesn't ship.
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://cache.numtide.com"
      "https://microvm.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzdCnor1een6jaXL68+4="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSeBc="
    ];
  };
  outputs =
    { self
    , home-manager
    , nixpkgs
    , nixpkgs-unstable
    , nixpkgs-master
    , nixos-hardware
    , darwin
    , fenix
    , sops-nix
    , hyprland
    , nix-homebrew
    , homebrew-core
    , homebrew-cask
    , homebrew-bundle
    , homebrew-nikitabobko
    , librus-notifications
    , jump
    , llm-agents
    , peon-ping
    , microvm
    , eink-bridge
    , nix-openclaw
    , ...
    }@inputs:
    let
      default_system = "x86_64-linux";

      insecurePackages = [
        # In use: electron-39 (obsidian/slack on amd-pc+dell-xps), minio
        # (services.minio on amd-pc). Re-audit if those apps/services are dropped.
        "electron-39.8.10"
        "minio-2025-10-15T17-29-55Z"
      ];

      karabinerOverlay = (self: super: {
        karabiner-elements = super.karabiner-elements.overrideAttrs (old: {
          version = "14.13.0";
          src = super.fetchurl {
            inherit (old.src) url;
            hash = "sha256-gmJwoht/Tfm5qMecmq1N6PSAIfWOqsvuHU8VDJY8bLw=";
          };
        });
      });

      lspmuxOverlay = (final: prev: {
        lspmux = prev.lspmux.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            ./patches/lspmux-init-notifications.patch
          ];
        });
      });

      paperlessOverlay = (final: prev: {
        paperless-ngx = prev.paperless-ngx.overrideAttrs (old: {
          doCheck = false;
        });
      });

      mkPkgs =
        nixpkgsInput:
        { extraConfig ? { }, overlays ? [ ] }:
        system:
        let
          overlayList = overlays;
        in
        import nixpkgsInput {
          inherit system;
          config = {
            allowUnfree = true;
            allowUnfreePredicate = (_: true);
          } // extraConfig;
          overlays = overlayList;
        };

      pkgs-stable = mkPkgs nixpkgs {
        extraConfig = {
          permittedInsecurePackages = insecurePackages;
        };
        overlays = [ karabinerOverlay paperlessOverlay ];
      };

      pkgs-default = pkgs-stable default_system;

      pkgs-unstable = mkPkgs nixpkgs-unstable {
        extraConfig = {
          permittedInsecurePackages = insecurePackages ++ [
            "electron-32.3.3"
          ];
        };
        overlays = [ lspmuxOverlay ];
      };

      pkgs-master = mkPkgs nixpkgs-master {
        extraConfig = {
          permittedInsecurePackages = [
            "electron-32.3.3"
          ];
        };
      };


      mkHostWithModules = hostName: system: extraModules:
        nixpkgs.lib.nixosSystem {
          pkgs = pkgs-stable system;
          specialArgs = {
            pkgs-unstable = pkgs-unstable system;
            pkgs-master = pkgs-master system;
            pkgs-default = pkgs-stable system;

            # make all inputs availabe in other nix files
            inherit inputs;
          };

          modules = [
            # Root on ZFS related configuration
            ./modules

            # Configuration shared by all hosts
            ./configuration.nix

            # Configuration shared by all linux hosts
            ./configuration_linux.nix

            # Configuration per host
            # Be sure to include all other modules in ./hosts/${hostName}/default.nix
            ./hosts/${hostName}

            # AMD-specific hardware optimizations for amd-pc
            (if hostName == "amd-pc" then nixos-hardware.nixosModules.common-cpu-amd else { })

            # librus-notifications module for odroid
            (if hostName == "odroid" then librus-notifications.nixosModules.default else { })

            # home-manager
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = {
                inherit inputs;
                pkgs-unstable = pkgs-unstable system;
                pkgs-master = pkgs-master system;
                llm-agents-pkgs = llm-agents.packages.${system};
                flakeRoot = toString ./.;
              };
              home-manager.sharedModules = [
                sops-nix.homeManagerModules.sops
                peon-ping.homeManagerModules.default
              ];
              home-manager.users.flakm = import ./home-manager/${hostName}.nix;
            }

            # fenix
            {
              nixpkgs.overlays = [
                fenix.overlays.default
              ];
            }

            sops-nix.nixosModules.sops
          ] ++ extraModules;
        };

      mkHost = hostName: system: mkHostWithModules hostName system [ ];

      mkDarwinHost =
        { hostName
        , userName
        , homeManagerConfig
        , extraModules ? [ ]
        , homeManagerSharedModules ? [ ]
        , homeManagerBackupFileExtension ? null
        }:
        let
          system = "aarch64-darwin";
        in
        darwin.lib.darwinSystem {
          inherit system;
          specialArgs = {
            pkgs-unstable = pkgs-unstable system;
            pkgs-master = pkgs-master system;
            pkgs = pkgs-stable system;
            inherit inputs;
          };
          modules = [
            ./configuration.nix
            ./hosts/${hostName}
            home-manager.darwinModules.home-manager
            nix-homebrew.darwinModules.nix-homebrew
          ] ++ extraModules ++ [
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = {
                inherit inputs;
                pkgs-unstable = pkgs-unstable system;
                pkgs-master = pkgs-master system;
                llm-agents-pkgs = llm-agents.packages.${system};
                flakeRoot = toString ./.;
              };
              home-manager.sharedModules = homeManagerSharedModules;
              home-manager.users.${userName} = import homeManagerConfig;
              system.primaryUser = userName;
            }
          ] ++ nixpkgs.lib.optional (homeManagerBackupFileExtension != null) {
            home-manager.backupFileExtension = homeManagerBackupFileExtension;
          };
        };

    in
    {
      formatter.x86_64-linux = pkgs-default.nixpkgs-fmt;
      formatter.aarch64-darwin = (pkgs-stable "aarch64-darwin").nixpkgs-fmt;

      fonts.packages = [
        nixpkgs.nerd-fonts.fira-code
      ];

      # NixOS configuration entrypoint
      # Available through 'nixos-rebuild --flake .#your-hostname'
      nixosConfigurations = {
        dell-xps = mkHost "dell-xps" "x86_64-linux";
        odroid = mkHost "odroid" "x86_64-linux";
        odroid-router = mkHostWithModules "odroid" "x86_64-linux" [ ./hosts/odroid/router.nix ];
        router = mkHost "router" "x86_64-linux";
        amd-pc = mkHost "amd-pc" "x86_64-linux";
      };


      darwinConfigurations.air = mkDarwinHost {
        hostName = "air";
        userName = "maciek";
        homeManagerConfig = ./home-manager/air.nix;
        homeManagerSharedModules = [
          sops-nix.homeManagerModules.sops
        ];
      };

      darwinConfigurations.work = mkDarwinHost {
        hostName = "work";
        userName = "flakm";
        homeManagerConfig = ./home-manager/work.nix;
        extraModules = [
          sops-nix.darwinModules.sops
        ];
        homeManagerSharedModules = [
          sops-nix.homeManagerModules.sops
          peon-ping.homeManagerModules.default
        ];
        homeManagerBackupFileExtension = "hm-bak";
      };


    };
}
