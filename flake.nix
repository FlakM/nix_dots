{
  description = "Macieks's system config";

  inputs = {
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur.url = "github:nix-community/NUR";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-stable.follows = "nixpkgs";
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
        pkgs = pkgs-stable default_system;
        extraSpecialArgs = {
          inherit inputs outputs;
          pkgs-unstable = pkgs-unstable default_system;
          pkgs-master = pkgs-master default_system;
        }; # this is the important part

        modules = [
          nur.nixosModules.nur
          ./home-manager/${hostName}.nix
        ] ++ modules;
      };
    in
    {
      formatter.x86_64-linux = pkgs-default.nixpkgs-fmt;

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




      # Standalone home-manager configuration entrypoint
      # Available through 'home-manager --flake .#your-username@your-hostname'
      homeConfigurations = {
        "flakm@dell-xps" = mkHomeManager "flakm" "dell-xps" "x86_64-linux" [ ];
        "flakm@amd-pc" = mkHomeManager "flakm" "amd-pc" "x86_64-linux" [ ];
        "flakm@odroid" = mkHomeManager "flakm" "odroid" "x86_64-linux" [ ];
        "maciek@air" = mkHomeManager "maciek" "air" "aarch64-darwin" [ ];
      };



      packages.x86_64-linux =
        let
          headers = pkgs-default.dockerTools.buildImage {
            name = "headers";
            tag = "latest";
            copyToRoot = pkgs-default.buildEnv {
              name = "image-root";
              paths = with pkgs-default; [ dockerTools.usrBinEnv dockerTools.binSh bcc busybox ];
              pathsToLink = [ "/bin" ];
            };

            config.Cmd = [ "/bin/sh" ];
          };

        in
        {
          default = fenix.packages.x86_64-linux.beta.toolchain;
          bcc = headers;
        };
    };
}
