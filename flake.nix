{
  description = "Macieks's system config";

  inputs = {
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur.url = "github:nix-community/NUR";

  };
  outputs =
    { self
    , home-manager
    , nixpkgs
    , nixpkgs-unstable
    , nixpkgs-master
    , nixos-hardware
    , fenix
    , nur
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
        (nerdfonts.override { fonts = [ "Roboto Mono" ]; })
      ];

      # NixOS configuration entrypoint
      # Available through 'nixos-rebuild --flake .#your-hostname'
      nixosConfigurations = {
        dell-xps = mkHost "dell-xps" "x86_64-linux";
        odroid = mkHost "odroid" "x86_64-linux";
        amd-pc = mkHost "amd-pc" "x86_64-linux";
      };

      # Standalone home-manager configuration entrypoint
      # Available through 'home-manager --flake .#your-username@your-hostname'
      homeConfigurations = {
        "flakm@dell-xps" = mkHomeManager "flakm" "dell-xps" "x86_64-linux" [ ];
        "flakm@amd-pc" = mkHomeManager "flakm" "amd-pc" "x86_64-linux" [ ];
        "flakm@odroid" = mkHomeManager "flakm" "odroid" "x86_64-linux" [ ];
      };
    };
}
