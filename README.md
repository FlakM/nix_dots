# My dotfiles using nix flakes



## Installation for linux

```
sudo nixos-rebuild switch --flake ~/programming/flakm/.nixpkgs#dell-xps 
```

## Installation for darwin

1. Install nix package manaeger in [deamon mode](https://nixos.org/manual/nix/stable/installation/installing-binary.html?highlight=uninstall#multi-user-installation)
2. Install nix darwin using [instructions](https://github.com/LnL7/nix-darwin)
3. Download dotfiles:

```bash
git clone https://github.com/FlakM/nix_dots.git
cd nix_dots/nix_config
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
darwin-rebuild switch --flake ~/nix_dots/nix_config#m1pro
```

### Add custom dir flake

#### Scala project

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

If you dont want to commit the flake files you might:

```
git add --intent-to-add flake.* -f
git update-index --assume-unchanged flake.*
```

TODO this one uses correct java version but unfortunately the bloop is not included... 


## Additional things to install on macs

1. rancher docs: https://rancherdesktop.io/ 
2. import key

```bash
cat > ~/.ssh/id_rsa_yubikey.pub <<EOF
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDh6bzSNqVZ1Ba0Uyp/EqThvDdbaAjsJ4GvYN40f/p9Wl4LcW/MQP8EYLvBTqTluAwRXqFa6fVpa0Y9Hq4kyNG62HiMoQRjujt6d3b+GU/pq7NN8+Oed9rCF6TxhtLdcvJWHTbcq9qIGs2s3eYDlMy+9koTEJ7Jnux0eGxObUaGteQUS1cOZ5k9PQg+WX5ncWa3QvqJNxx446+OzVoHgzZytvXeJMg91gKN9wAhKgfibJ4SpQYDHYcTrOILm7DLVghrcU2aFqLKVTrHSWSugfLkqeorRadHckRDr2VUzm5eXjcs4ESjrG6viKMKmlF1wxHoBrtfKzJ1nR8TGWWeH9NwXJtQ+qRzAhnQaHZyCZ6q4HvPlxxXOmgE+JuU6BCt6YPXAmNEMdMhkqYis4xSzxwWHvko79NnKY72pOIS2GgS6Xon0OxLOJ0mb66yhhZB4hUBb02CpvCMlKSLtvnS+2IcSGeSQBnwBw/wgp1uhr9ieUO/wY5K78w2kYFhR6Iet55gutbikSqDgxzTmuX3Mkjq0L/MVUIRAdmOysrR2Lxlk692IrNYTtUflQLsSfzrp6VQIKPxjfrdFhHIfbPoUdfMf+H06tfwkGONgcej56/fDjFbaHouZ357wcuwDsuMGNRCdyW7QyBXF/Wi28nPq/KSeOdCy+q9KDuOYsX9n/5Rsw== cardno:000614320136
EOF
chmod 600 ~/.ssh/id_rsa_yubikey.pub

cat << EOF >> ~/.ssh/config
Host github.com
    IdentitiesOnly yes
    IdentityFile ~/.ssh/id_rsa_yubikey.pub
EOF

gpg --card-status


ssh git@github.com -vvv


gpg --recv 0x6B872E24F09A547E
export KEYID=0x6B872E24F09A547E
# trust completly
gpg --edit-key $KEYID


gpg --output public.pgp --armor --export maciej.jan.flak@gmail.com

```


## TODO

1. alacritty does not keep enough long buffer? only 70 lines
2. some gpg ssh configuration should be managed by home manager
- id_rsa_yubikey.pub
- ~/.ssh/config
- public gpg key for trust

