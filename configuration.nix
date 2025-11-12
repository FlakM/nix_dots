# configuration in this file is shared by all hosts

{ pkgs, ... }: {
  # Enable NetworkManager for wireless networking,
  # You can configure networking with "nmtui" command.
  #networking.useDHCP = true;
  #networking.networkmanager.enable = false;

  programs = {
    zsh.enable = true;
  };

  environment.systemPackages = with pkgs; [
    jq
    yq-go
    lsof
    cachix # binary cache cli tool
    nvd
  ];



}
