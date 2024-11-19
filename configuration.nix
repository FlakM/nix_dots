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
