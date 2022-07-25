# My dotfiles using nix flakes


## Installation

1. Install nix package manaeger in [deamon mode](https://nixos.org/manual/nix/stable/installation/installing-binary.html?highlight=uninstall#multi-user-installation)
2. Install nix darwin using [instructions](https://github.com/LnL7/nix-darwin)
3. Download dotfiles:

```bash
git clone https://github.com/FlakM/nix_dots.git
cd nix_dots/.nixpkgs
# install nix flakes
nix-env -iA nixpkgs.nixFlakes

```
4. Enable flakes. Edit `/etc/nix/nix.conf` by adding line:

```
experimental-features = nix-command flakes
```


## Usage

### Apply changes

1. Modify `*.nix` files and execute following command:

```bash
darwin-rebuild switch --flake ~/nix_dots/.nixpkgs
```

### Add custom dir flake

Add `flake.nix` to current directory:

```nix
{
  description = "my project description";

  inputs = {
    typelevel-nix.url = "github:typelevel/typelevel-nix";
    nixpkgs.follows = "typelevel-nix/nixpkgs";
    flake-utils.follows = "typelevel-nix/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, typelevel-nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ typelevel-nix.overlay ];
        };
      in
      {
        devShell = pkgs.devshell.mkShell {
          imports = [ typelevel-nix.typelevelShell ];
          name = "my-project-shell";
          typelevelShell = {
		    jdk.package = pkgs.jdk8;
          };
        };
      }
    );
}
```

Activate `direnv`:

```bash
echo "use flake" >> .envrc && direnv allow
```

TODO this one uses correct java version but unfortunately the bloop is not included... 
