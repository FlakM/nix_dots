{
  description = "Macieks's system config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    nixpkgs-unstable.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    darwin = { 
	url = "github:lnl7/nix-darwin/master";
        inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , darwin
    , home-manager
    , nixpkgs
    , nixpkgs-unstable
    , ...
    }@inputs:
    {
    fonts.fonts = with nixpkgs; [
      (nerdfonts.override { fonts = [ "Roboto Mono" ]; })
    ];
      darwinConfigurations.m1pro =
        let
          mkIntelPackages = source: import source {
            localSystem = "x86_64-darwin";
          };

          pkgs_x86 = mkIntelPackages nixpkgs;

          arm-overrides = final: prev: {
            inherit (pkgs_x86) openconnect; # scala-cli;
            bloop = pkgs_x86.bloop;
            #bloop = pkgs_x86.bloop.override { jre = prev.openjdk11; };
          };

        in
        darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            {
              nixpkgs.overlays = [
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
