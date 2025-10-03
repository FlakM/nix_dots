{ config, pkgs, pkgs-unstable, pkgs-master, lib, ... }: {

  home.packages = [
    pkgs-master.claude-code
    pkgs-master.codex
    pkgs-master.gemini-cli
    pkgs-master.cursor-cli
  ];

}
