{
  description = "Macieks's system config";

  inputs = {
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur.url = "github:nix-community/NUR";

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
    , nur
    , sops-nix
    , hyprland
    , nix-homebrew
    , homebrew-core
    , homebrew-cask
    , homebrew-bundle
    , ...
    }@inputs:
    let
      inherit (self) outputs;

      default_system = "x86_64-linux";

      pkgs-stable = system: import nixpkgs {
        inherit system;
        # settings to nixpkgs goes to here
        allowUnfree = true;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = (_: true);
          permittedInsecurePackages = [
            "dotnet-sdk-6.0.428"
            "aspnetcore-runtime-6.0.36"
          ];

        };
        overlays = [
          # workaround for bug https://github.com/LnL7/nix-darwin/issues/1041
          # it resulted in error ".... .karabiner_grabber.plist': No such file or directory"
          (self: super: {
            karabiner-elements = super.karabiner-elements.overrideAttrs (old: {
              version = "14.13.0";

              src = super.fetchurl {
                inherit (old.src) url;
                hash = "sha256-gmJwoht/Tfm5qMecmq1N6PSAIfWOqsvuHU8VDJY8bLw=";
              };
            });
          })
        ];
      };

      pkgs-default = pkgs-stable default_system;

      pkgs-unstable = system: import nixpkgs-unstable {
        inherit system;
        allowUnfree = true;

        permittedInsecurePackages = [
          "electron-32.3.3"
        ];
        config = {
          allowUnfree = true;
          allowUnfreePredicate = (_: true);

          permittedInsecurePackages = [
            "dotnet-sdk-6.0.428"
            "aspnetcore-runtime-6.0.36"
          ];
        };
      };
      pkgs-master = system: import nixpkgs-master {
        inherit system;
        allowUnfree = true;

        permittedInsecurePackages = [
          "electron-32.3.3"
        ];
        config = {
          allowUnfree = true;
          allowUnfreePredicate = (_: true);
        };
      };


      mkHost = hostName: system:
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
            (if hostName == "amd-pc" then nixos-hardware.nixosModules.common-cpu-amd else {})

            # home-manager
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }

            # fenix
            {
              nixpkgs.overlays = [
                fenix.overlays.default


                # pull just averaged_perceptron_tagger_eng from pkgs-unstable
                (self: super: {
                })

              ];
            }

            sops-nix.nixosModules.sops
          ];
        };

      mkHomeManager = user: hostName: system: modules: home-manager.lib.homeManagerConfiguration {
        pkgs = pkgs-stable system;
        extraSpecialArgs = {
          inherit inputs outputs;
          pkgs-unstable = pkgs-unstable system;
          pkgs-master = pkgs-master system;
        }; # this is the important part



        modules = [
          ./home-manager/${hostName}.nix
          sops-nix.homeManagerModules.sops
        ] ++ modules;
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
        amd-pc = mkHost "amd-pc" "x86_64-linux";
      };


      darwinConfigurations.air =
        darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = {
            pkgs-unstable = pkgs-unstable "aarch64-darwin";
            pkgs-master = pkgs-master "aarch64-darwin";
            pkgs = pkgs-stable "aarch64-darwin";

            # make all inputs availabe in other nix files
            inherit inputs;
          };
          modules = [
            ./configuration.nix
            ./hosts/air
            home-manager.darwinModules.home-manager
            nix-homebrew.darwinModules.nix-homebrew
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
            {
              users = {
                users = {
                  maciek = {
                    description = "maciek";
                    home = "/Users/maciek";
                  };
                };
              };
            }
          ];
        };

      darwinConfigurations.work =
        darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = {
            pkgs-unstable = pkgs-unstable "aarch64-darwin";
            pkgs-master = pkgs-master "aarch64-darwin";
            pkgs = pkgs-stable "aarch64-darwin";

            # make all inputs availabe in other nix files
            inherit inputs;
          };
          modules = [
            ./configuration.nix
            ./hosts/work
            home-manager.darwinModules.home-manager
            sops-nix.darwinModules.sops
            nix-homebrew.darwinModules.nix-homebrew
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
            {
              users = {
                users = {
                  flakm = {
                    description = "flakm";
                    home = "/Users/flakm";
                  };
                };
              };
            }
          ];
        };



      # Standalone home-manager configuration entrypoint
      # Available through 'home-manager --flake .#your-username@your-hostname'
      homeConfigurations = {
        "flakm@dell-xps" = mkHomeManager "flakm" "dell-xps" "x86_64-linux" [ ];
        "flakm@amd-pc" = mkHomeManager "flakm" "amd-pc" "x86_64-linux" [ ];
        "flakm@odroid" = mkHomeManager "flakm" "odroid" "x86_64-linux" [ ];
        "maciek@air" = mkHomeManager "maciek" "air" "aarch64-darwin" [ ];
        "flakm@work" = mkHomeManager "flakm" "work" "aarch64-darwin" [ ];
      };


    };
}
