# configuration in this file is shared by all hosts

{ pkgs, ... }: {
  # Enable NetworkManager for wireless networking,
  # You can configure networking with "nmtui" command.
  #networking.useDHCP = true;
  #networking.networkmanager.enable = false;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [
      "root"
      "flakm"
    ];

    # Hyprland cachix
    substituters = [
      "https://hyprland.cachix.org"
    ];
    trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  nix.gc = {
    automatic = true;
    options = "--delete-older-than 30d";
  };

  programs = {
    zsh.enable = true;
  };

  environment.systemPackages = builtins.attrValues {
    inherit (pkgs)
      jq
      yq-go
      lsof
      cachix# binary cache cli tool
      nvd
      ;
  };



}
