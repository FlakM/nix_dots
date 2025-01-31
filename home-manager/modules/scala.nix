{ config, pkgs, pkgs-unstable, libs, ... }:
{

  home.packages = with pkgs; [
    pkgs-unstable.bloop
    scalafix
    scalafmt
    #sbt
    #     dotty
    pkgs-unstable.metals

    coursier

  ];


  programs.java = {
    enable = true;
    package = pkgs.zulu17;
  };


  # This adds JAVA_HOME to the global environment, by sourcing the jdk's
  # setup-hook on shell init. It is equivalent to starting a shell through 
  # 'nix-shell -p jdk', or roughly the following system-wide configuration:
  # 
  #   environment.variables.JAVA_HOME = ${pkgs.jdk.home}/lib/openjdk;
  #   environment.systemPackages = [ pkgs.jdk ];
  #  programs.java = {
  #    enable = true;
  #    package = pkgs.openjdk11;
  #  };

}
