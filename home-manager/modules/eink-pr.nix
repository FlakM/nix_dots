{ config, lib, pkgs, ... }:
let
  # The popup widget: paste a request + link, get a review workspace.
  launch = pkgs.writers.writePython3Bin "eink-pr-launch" {
    flakeIgnore = [ "E501" "E226" ];
  } (builtins.readFile ./eink-pr-launch.py);

  # What actually runs in the review pane. A wrapper rather than an inline command so
  # the pasted request never has to survive shell quoting: it arrives by file path.
  agent = pkgs.writeShellApplication {
    name = "eink-review-agent";
    text = ''
      seed="''${EINK_REVIEW_SEED:?EINK_REVIEW_SEED is not set — start the review from the eink-pr widget}"
      if [ ! -f "$seed" ]; then
        echo "eink-review-agent: seed prompt not found: $seed" >&2
        exit 1
      fi
      model="''${EINK_REVIEW_MODEL:-opencode-go/deepseek-v4.1-flash}"
      exec opencode mini --model "$model" --prompt "$(cat "$seed")"
    '';
  };
in
{
  options.einkPr.launch = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    description = "The eink-pr launcher, bound to a herdr popup key.";
  };

  config = {
    einkPr.launch = launch;
    home.packages = [ launch agent ];
  };
}
