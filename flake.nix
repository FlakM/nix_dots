{
  description = "Macieks's system config";

  inputs = {
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur.url = "github:nix-community/NUR";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ghostty = {
      url = "github:ghostty-org/ghostty";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";

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
    , nix-homebrew
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
        config = {
          allowUnfree = true;
          allowUnfreePredicate = (_: true);
        };
      };
      pkgs-master = system: import nixpkgs-master {
        inherit system;
        allowUnfree = true;
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

      fonts.fonts = with nixpkgs; [
        (nerdfonts.override { fonts = [ "FiraCode" ]; })
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
