# configuration in this file only applies to exampleHost host.
{ pkgs, ... }: {

  imports = [
    ../../shared/gpg.nix
  ];

  programs.tmux = {
    enable = true;
    newSession = true;
    terminal = "tmux-direct";
  };
  services.emacs.enable = false;

  environment.systemPackages = with pkgs; [
    home-manager
  ];
}
