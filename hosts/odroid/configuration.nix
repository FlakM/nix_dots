# configuration in this file only applies to exampleHost host.
{ pkgs, ... }: {

  imports = [
    ./nextcloud.nix
    ./tandoor.nix
    ./postgres.nix
  ];

  programs.tmux = {
    enable = true;
    newSession = true;
    terminal = "tmux-direct";
  };
  services.emacs.enable = false;

  environment.systemPackages = with pkgs; [
    home-manager
    tailscale
  ];

  # Let's open the UDP port with which the network is tunneled through
  networking.firewall = {
    allowedUDPPorts = [ 41641 ]; # tailscale
  };



  # enable the tailscale daemon; this will do a variety of tasks:
  # 1. create the TUN network device
  # 2. setup some IP routes to route through the TUN
  services.tailscale.enable = true;

}
