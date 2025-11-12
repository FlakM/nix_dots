{ lib, ... }:
{
  nix.settings = {
    experimental-features = lib.mkDefault [ "nix-command" "flakes" ];
    trusted-users = lib.mkForce [
      "root"
      "@wheel"
      "flakm"
    ];
    substituters = lib.mkDefault [
      "https://hyprland.cachix.org"
    ];
    trusted-public-keys = lib.mkDefault [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  nix.gc = {
    automatic = lib.mkDefault true;
    options = lib.mkDefault "--delete-older-than 30d";
  };
}
