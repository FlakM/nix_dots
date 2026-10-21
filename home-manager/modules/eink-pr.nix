{ config, lib, pkgs, ... }:
let
  # The popup widget: paste a request + link, get a review workspace.
  launch = pkgs.writers.writePython3Bin "eink-pr-launch" {
    flakeIgnore = [ "E501" "E226" ];
  } (builtins.readFile ./eink-pr-launch.py);

  # What actually runs in the review pane. A wrapper rather than an inline command so
  # the pasted request never has to survive shell quoting: it arrives by file path.
  #
  # The agent is chosen per repository: Coralogix work needs internal tooling that only
  # Claude Code carries, so those reviews open Claude Code. Everything else runs OpenCode
  # with a cheap orchestrating model.
  agent = pkgs.writeShellApplication {
    name = "eink-review-agent";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      seed="''${EINK_REVIEW_SEED:?EINK_REVIEW_SEED is not set — start the review from the eink-pr widget}"
      if [ ! -f "$seed" ]; then
        echo "eink-review-agent: seed prompt not found: $seed" >&2
        exit 1
      fi
      kind="''${EINK_REVIEW_AGENT:-opencode}"
      # OpenCode needs a model; Claude's default is the account's model unless one is named.
      default_model=""
      if [ "$kind" = "opencode" ]; then
        default_model="opencode-go/deepseek-v4.1-flash"
      fi
      model="''${EINK_REVIEW_MODEL:-$default_model}"
      prompt="$(cat "$seed")"

      case "$kind" in
        claude)
          # A new worktree is an untrusted path: without this, Claude stops at the
          # folder-trust dialog before it ever reads the seed. This is a dedicated review
          # workspace, so the bypass is bounded to it.
          if [ -n "$model" ]; then
            exec claude --dangerously-skip-permissions --model "$model" "$prompt"
          fi
          exec claude --dangerously-skip-permissions "$prompt"
          ;;
        opencode)
          exec opencode mini --model "$model" --prompt "$prompt"
          ;;
        *)
          echo "eink-review-agent: unknown EINK_REVIEW_AGENT: $kind" >&2
          exit 1
          ;;
      esac
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
