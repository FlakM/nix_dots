{
  description = "Macieks's system config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
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

  };

  outputs =
    { self
    , darwin
    , home-manager
    , nixpkgs
    , nixpkgs-unstable
    , nixpkgs-master
    , nixos-hardware
    , hyprland
    , nur
    , ...
    }@inputs:
    let
      inherit (self) outputs;
      # Inject 'unstable' and 'trunk' into the overridden package set, so that
      # the following overlays may access them (along with any system configs
      # that wish to do so).
      pkg-sets = (
        final: prev: {
          unstable = import inputs.nixpkgs-unstable {
            system = final.system;
            allowUnfree = true;
            config = {
              allowUnfree = true;
              allowUnfreePredicate = (_: true);
            };
          };
          master = import inputs.nixpkgs-master {
            system = final.system;
            allowUnfree = true;
            config = {
              allowUnfree = true;
              allowUnfreePredicate = (_: true);
            };
          };
        }
      );

      mkHost = hostName: system:
        (({ zfs-root, pkgs, system, ... }:
          nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = { inherit inputs outputs; }; # this is the important part
            modules = [
              nur.nixosModules.nur
              {
                nixpkgs.overlays = [
                  pkg-sets
                ];
              }

              # Module 0: zfs-root
              ./modules

              # Module 1: host-specific config, if exist
              (if (builtins.pathExists
                ./hosts/${hostName}/configuration.nix) then
                (import ./hosts/${hostName}/configuration.nix {
                  inherit pkgs inputs;
                  lib = pkgs.lib;
                })
              else
                { })

              # Module 2: entry point
              (({ zfs-root, pkgs, lib, ... }: {
                inherit zfs-root;
                system.configurationRevision =
                  if (self ? rev) then
                    self.rev
                  else
                    throw "refuse to build: git tree is dirty";
                system.stateVersion = "23.05";
                imports = [
                  "${nixpkgs}/nixos/modules/installer/scan/not-detected.nix"
                  # "${nixpkgs}/nixos/modules/profiles/hardened.nix"
                  # "${nixpkgs}/nixos/modules/profiles/qemu-guest.nix"
                ];
              }) {
                inherit zfs-root pkgs;
                lib = nixpkgs.lib;
              })

              # Module 3: home-manager
              home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
              }

              # Module 4: config shared by all hosts
              (import ./configuration.nix { inherit pkgs; })
            ];
          })

          # configuration input
          (import ./hosts/${hostName} {
            system = system;
            pkgs = import inputs.nixpkgs { system = "x86_64-linux"; allowUnfree = true; config = { allowUnfree = true; allowUnfreePredicate = (_: true); }; };
          }));
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
            wayland.windowManager.hyprland.enable = true;
          }
          ./home-manager/modules/hyprland.nix
        ];
      };

      homeConfigurations."flakm@odroid" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;

        extraSpecialArgs = { inherit inputs outputs; }; # this is the important part

        modules = [
          nur.nixosModules.nur
          {
            nixpkgs.overlays = [
              pkg-sets
            ];
          }
          ./home-manager/odroid.nix
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

        amd-pc2 =
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
                  (self: super: {
                    openfortivpn = super.openfortivpn.overrideAttrs (old: {
                      #src = super.fetchFromGitHub {
                      #  owner = "adrienverge";
                      #  repo = "openfortivpn";
                      #  rev = "master";
                      #  hash = "sha256-jbgxhCQWDw1ZUOAeLhOG+b6JYgvpr5TnNDIO/4k+e7k=";
                      #};
                      src = builtins.fetchTarball {
                        url = "https://github.com/adrienverge/openfortivpn/archive/master.tar.gz";
                        sha256 = "sha256:1fgx1vhj714n4ihjg4gm79iahlnxpnh7igvrlzmkwransikfj4r8";
                      };

                    });
                  })
                  #(final: prev: {
                  #  # very expensive since this invalidates the cache for a lot of (almost all) graphical apps.
                  #  xdg-utils = prev.xdg-utils.overrideAttrs (oldAttrs: {
                  #    postInstall = oldAttrs.postInstall + ''
                  #      # "overwrite" xdg-open with handlr
                  #      cp ${prev.writeShellScriptBin "xdg-open" "${prev.handlr}/bin/handlr open \"$@\""}/bin/xdg-open $out/bin/xdg-open
                  #    '';
                  #  });
                  #})
                ];
              }
            ];
          };
        odroid = mkHost "odroid" "x86_64-linux";
        amd-pc = mkHost "amd-pc" "x86_64-linux";
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
