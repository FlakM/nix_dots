{ config, pkgs, pkgsUnstable, libs, ... }:
{

  home.packages = with pkgs; [
    git
  ];

  programs.git = {
    enable = true;
    userName  = "FlakM";
    userEmail = "maciej.jan.flak@gmail.com";
    # mac os is messed up...
    signing = {
       key = "AD7821B8";
       signByDefault = true;
    };

    delta.enable = true;
    lfs.enable = true;

    ignores = [
      "shell.nix"
      ".metals"
      ".bloop"
      "out"
      ".envrc"
      ".history/"
      "**/project/metals.sbt"
      ".idea/"
      ".vscode/settings.json"
      ".bloop/"
      ".bsp/"
      ".scala-build/"
      ".direnv/"
      "flake.nix"
      "flake.lock"
    ];
    
    extraConfig = {
      pull = { ff = "only"; };
      init.defaultBranch = "main";
    };
  };
}
