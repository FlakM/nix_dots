{ pkgs, inputs, ... }:
{
  programs.peon-ping = {
    enable = true;
    package = inputs.peon-ping.packages.${pkgs.system}.default;
    settings = {
      default_pack = "rick-and-morty";
      volume = 0.5;
      enabled = true;
      categories = {
        "session.start" = true;
        "task.complete" = true;
        "task.error" = true;
        "input.required" = true;
        "resource.limit" = true;
        "user.spam" = true;
        "task.acknowledge" = false;
      };
    };
    installPacks = [
      {
        name = "rick-and-morty";
        src = pkgs.fetchFromGitHub {
          owner = "Mr3zee";
          repo = "peonping-rick-and-morty";
          rev = "258089e44c579748895c21795fababd4ec83faab";
          sha256 = "sha256-rVdu67Ew/X1BUuRimzAghosDVjGgE4U8x++E8QfkwSc=";
        };
      }
    ];
  };
}
