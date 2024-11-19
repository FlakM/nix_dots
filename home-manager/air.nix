{ config, lib, pkgs, ... }:

{
  imports = [
    ./modules/home-manager.nix
    ./modules/common.nix

    # todo uncomment when i fix it
    #./modules/nvim/neovim.nix
    ./modules/rust.nix
    ./modules/tmux.nix
    ./modules/git.nix
    ./modules/gpg_home.nix


    ./modules/yubikey.nix

    ./modules/atuin.nix
    ./modules/kitty.nix
    ./modules/starship.nix
    ./modules/zsh.nix
  ];


  home = {
    username = "maciek";
    homeDirectory = "/Users/maciek";
    stateVersion = "24.05";
  };

}
