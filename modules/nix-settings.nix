{ lib, ... }:
{
  nix.settings = {
    experimental-features = lib.mkDefault [ "nix-command" "flakes" ];
    trusted-users = lib.mkForce [
      "root"
      "@wheel"
      "flakm"
    ];
    extra-substituters = [
      "https://hyprland.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSeBc="
    ];
    max-jobs = lib.mkDefault "auto";
    cores = lib.mkDefault 0;
    http-connections = lib.mkDefault 128;
    connect-timeout = lib.mkDefault 5;
    keep-outputs = lib.mkDefault true;
    keep-derivations = lib.mkDefault true;
  };

  nix.gc = {
    automatic = lib.mkDefault true;
    options = lib.mkDefault "--delete-older-than 30d";
  };
}
