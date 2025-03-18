# My dotfiles using nix flakes with home manager

![Screenshot of two appliactions open terminal on the left and firefox on the right](./screen.png)

The why for this repo is to have a reproducible setup for my different machines.
I have a linux machines and work macs. Since they cannot share all of the software like DMs I try to keep the configuration as close as possible to avoid context switching. It results in some overhead and strange key combinations but I think it is worth it.

My hardware setup is a ultra wide monitor with a kvm connected to two machines.

## Features

This is a set of very opinionated configurations. The mix of shortcuts is a result of fighting with different operating machines and picking the lowest common denominator.

1. Window managment with `hyprland` and `aerospace`. Meant to jump quickly between stable "activities" like coding, browsing, notes etc.
    - `alt + NUM` go to workspace
    - `alt + shift + NUM` move windows to workspace
    - `ctrl + shift + h/j/k/l` move focus
    - `ctrl + alt + shift + h/j/k/l` resize windows
    - `ctrl + alt + h/j/k/l` move windows
    - `alt + [NUM]` move windows to workspace
    - pin applications to workspaces:
        - 1: terminals (kitty)
        - 2: browser (firefox)
        - 3: notes
        - 0: slack 
2. `neovim` as main editor living mostly in long lived `tmux` sessions
    - pretty default settings (disabled arrow keys, line numbers, relative numbers)
    - debugging support 
    - `ctrl + w + h/j/k/l` move between splits
    - `ctrl + w + v/s` split windows (vertical/horizontal)
    - `ctrl + w + o` close other windows
    - `leader + c + g` for copying url to git code to share (works in both visual and normal mode)
    - `leader + f` for fuzzy finding files
    - `leader + f + g` for grepping in files
    - `leader + f + m` for fuzzy searching marks
    - `ctrl + s` for accepting AI code completions
    - `leader + c + f` copy relative file path
    - `leader + c + t` copy file name
    - LSP shortcuts defined in [lsp-config.lua](./home-manager/modules/nvim/config/lsp-config.lua)
        - `gd` for going to definition 
        - `gtd` for going to type definition
        - `gr` for references
        - `gi` for implementation
        - `gds`/`gws` for document/workspace symbols
        - `leader + FF` for formatting
        - `leader + ca` for code actions
        - `]c` and `[c` for next/previous diagnostic
        - `leader + rn` for renaming
        - `leader + l` for enabling inlay hints (useful for rust)
3. `tmux` for managing terminals
    - `tmux new-session -c ~ -s main` for creating new session
    - `ctrl + b + c` for creating new window
    - `ctrl + b + NUM` for moving between windows [1-9]
    - `ctrl + b + ,` for renaming window
    - `ctrl + b + %` for splitting window
    - `ctrl + b + h/j/k/l` for moving between splits
    - `ctrl + b + [h/j/k/l]` for resizing splits
    - `ctrl + b + z` for zooming in/out
    - `ctrl + b + d` for detaching
    - `ctrl + b + [` for scrolling
    - `ctrl + b + r` for reloading config
    - `ctrl + b + s/w` for quick switching between sessions/windows
4. terminal emulator with `zsh`
    - `atuin` for magic history search
        - `ctrl + r` for searching history, press again to change search type (session, host etc)
        - `up` in zsh for history session in current session
    - `zoxide` for jumping between directories. Write `z pattern` to jump to directory containing `pattern`
    - `starship` for nicer prompt
    - `vim mode` in `zsh`
        - press `esc` to enter normal mode
        - enter `v` in normal mode to enter visual mode using default `$EDITOR` - useful for editing long commands
        - normal vim navigation works in normal mode




## How to use

### On local machine

1. Clone repo into local dir `git clone git@github.com:FlakM/nix_dots.git` 
2. Develop ie on `amd-pc` host
3. Switch nixos `sudo nixos-rebuild switch --flake ~/programming/flakm/nix_dots#amd-pc`
4. Switch home manager `home-manager --flake ~/programming/flakm/nix_dots#flakm@amd-pc switch`


### On remote machine ie odroid

1. Build locally and send paths over ssh and switch `nixos-rebuild switch --target-host flakm@192.168.0.102  --use-remote-sudo --flake ~/programming/flakm/nix_dots#odroid`
2. Build locally home manager: `home-manager --flake ~/programming/flakm/nix_dots#flakm@odroid build`
3. Ship over ssh: `nix copy --to ssh://flakm@192.168.0.102 ./result`
4. Apply changes: `home-manager --flake github:flakm/nix_dots#flakm@odroid switch`

### On mac m1

1. Clone repo into local dir `git clone git@github.com:FlakM/nix_dots.git` 
2. Follow [instructions](https://github.com/LnL7/nix-darwin?tab=readme-ov-file#flakes) to install nix-darwin. To change the machine name:
```bash
sudo scutil --set ComputerName "air"
sudo scutil --set HostName "air"
sudo scutil --set LocalHostName "air"
```
3. Install changes `nix  run nix-darwin -- switch --flake ~/programming/flakm/nix_dots`

### Add custom project with dev-shell and direnv integration


#### Example project

Add `flake.nix` to current directory:

```nix
{
  description = "A simple devshell with cowsay";

  # Flake inputs
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  # Outputs of our flake
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in {
        devShell = pkgs.mkShell {
          buildInputs = [
            pkgs.cowsay
          ];

          shellHook = ''
            echo "Welcome to the devshell!"
            cowsay "Moo! I'm here to help you with your coding tasks!"
          '';
        };
      });
}
```

Activate `direnv`:

```bash
echo "use flake" >> .envrc && direnv allow
```

If you dont want to commit the flake files you might:

```bash
git add --intent-to-add flake.* -f
git update-index --assume-unchanged flake.*
```

#### Example rust project

Just crane it!

```bash
# Start with a comprehensive suite of tests
nix flake init -t github:ipetkov/crane#quick-start
```


## Additional things to install (todo check if still required)

1. import gpg key

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

#### Manage secrets

Insert yubikey and run:

```bash
nix-shell -p sops --run "sops secrets/secrets.yaml"
```
