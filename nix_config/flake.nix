{
  description = "Macieks's system config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-23.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland.url = "github:hyprwm/Hyprland";
    nur.url = "github:nix-community/NUR";

    alacritty-theme.url = "github:alexghr/alacritty-theme.nix";
  };

  outputs =
    { self
    , darwin
    , home-manager
    , nixpkgs
    , nixpkgs-unstable
    , nixos-hardware
    , hyprland
    , nur
    , alacritty-theme
    , ...
    }@inputs:
    let
      inherit (self) outputs;
      pkg-sets = (
        final: prev: {
          unstable = import inputs.nixpkgs-unstable { system = final.system; };
        }
      );
    in
    {

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;
      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixpkgs-fmt;
      fonts.fonts = with nixpkgs; [
        (nerdfonts.override { fonts = [ "Roboto Mono" ]; })
      ];

      # Standalone home-manager configuration entrypoint
      # Available through 'home-manager --flake .#your-username@your-hostname'
      homeConfigurations."flakm@amd-pc" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;

        extraSpecialArgs = { inherit inputs outputs; }; # this is the important part

        modules = [
          nur.nixosModules.nur
          {
            nixpkgs.overlays = [
              pkg-sets
            ];
          }
          #home-manager.nixosModules.home-manager
          ./home-manager/amd-pc.nix
          #{
          #  #useGlobalPkgs = true;
          #  #useUserPackages = true;
          #  users.flakm = import ./home-manager/amd-pc.nix;
          #}
          hyprland.homeManagerModules.default
          {
            wayland.windowManager.hyprland = {
              enable = true;
              xwayland = {
                enable = true;
                #hidpi = true;
              };
            };
          }
          ./home-manager/modules/hyprland.nix
        ];
      };

      # NixOS configuration entrypoint
      # Available through 'nixos-rebuild --flake .#your-hostname'
      nixosConfigurations = {
        dell-xps =
          let
            # Inject 'unstable' and 'trunk' into the overridden package set, so that
            # the following overlays may access them (along with any system configs
            # that wish to do so).
            pkg-sets = (
              final: prev: {
                unstable = import inputs.nixpkgs-unstable { system = final.system; };
              }
            );

          in
          nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./dell-hardware-configuration.nix
              ./dell-configuration.nix
              ./gpg.nix
              nixos-hardware.nixosModules.dell-xps-15-9560-intel
              {
                nixpkgs.overlays = [
                  pkg-sets
                ];
              }
            ];
          };

        amd-pc =
          let
            # Inject 'unstable' and 'trunk' into the overridden package set, so that
            # the following overlays may access them (along with any system configs
            # that wish to do so).
            pkg-sets = (
              final: prev: {
                unstable = import inputs.nixpkgs-unstable { system = final.system; };
              }
            );

          in
          nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inherit inputs outputs; }; # this is the important part
            modules = [
              nur.nixosModules.nur
              ./wireguard.nix
              ./gpg.nix
              ./k3s.nix
              ./amd-pc-hardware-configuration.nix
              ./amd-pc-hardware-zfs-configuration.nix
              ./amd-pc-configuration.nix
              {
                nixpkgs.overlays = [
                  pkg-sets
                ];
              }
            ];
          };
      };

      darwinConfigurations.m1pro =
        let
          mkIntelPackages = source: import source {
            localSystem = "x86_64-darwin";
          };

          pkgs_x86 = mkIntelPackages nixpkgs-unstable;

          arm-overrides = final: prev: {
            inherit (pkgs_x86) openconnect; # scala-cli;
            unstable.bloop = pkgs_x86.bloop;
            #bloop = pkgs_x86.bloop.override { jre = prev.openjdk11; };
          };

          # Inject 'unstable' and 'trunk' into the overridden package set, so that
          # the following overlays may access them (along with any system configs
          # that wish to do so).
          pkg-sets = (
            final: prev: {
              unstable = import inputs.nixpkgs-unstable { system = final.system; };
            }
          );

        in
        darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            {
              nixpkgs.overlays = [
                pkg-sets
                arm-overrides
              ];
              nix.extraOptions = ''
                extra-platforms = x86_64-darwin
              '';
            }
            ./darwin-configuration.nix
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.mflak = import ./home-manager/pro.nix;
            }
            {
              users = {
                users = {
                  mflak = {
                    description = "Mflak";
                    home = "/Users/mflak";
                  };
                };
              };
            }
          ];
        };
    };

}
