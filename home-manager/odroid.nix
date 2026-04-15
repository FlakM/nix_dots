{ config, lib, pkgs, llm-agents-pkgs, ... }:

let
  SSH = "${pkgs.openssh}/bin/ssh -o BatchMode=yes -i /home/flakm/.ssh/ccusage_push flakm@amd-pc";
  JQ = "${pkgs.jq}/bin/jq";
  CURL = "${pkgs.curl}/bin/curl";
  CCUSAGE = "${llm-agents-pkgs.ccusage}/bin/ccusage";

  ccusage-push = pkgs.writeShellScript "ccusage-push" ''
    set -euo pipefail
    PUSHGATEWAY="http://127.0.0.1:9091"

    # --- daily historical ---
    DAILY=$(${SSH} ${CCUSAGE} daily --json 2>/dev/null) || { echo "ccusage: ssh failed, skipping"; exit 0; }
    {
      echo "# HELP ccusage_daily_cost_usd Daily Claude Code cost in USD"
      echo "# TYPE ccusage_daily_cost_usd gauge"
      echo "$DAILY" | ${JQ} -r '.daily[] | "ccusage_daily_cost_usd{date=\"\(.date)\"} \(.totalCost)"'

      echo "# HELP ccusage_daily_model_cost_usd Daily cost by model in USD"
      echo "# TYPE ccusage_daily_model_cost_usd gauge"
      echo "$DAILY" | ${JQ} -r '.daily[] as $d | $d.modelBreakdowns[] | select(.modelName != null) | "ccusage_daily_model_cost_usd{date=\"\($d.date)\",model=\"\(.modelName)\"} \(.cost)"'
    } | ${CURL} --silent --data-binary @- "$PUSHGATEWAY/metrics/job/ccusage"

    # --- all blocks (for active block metrics + today's running total) ---
    TODAY_DATE=$(${pkgs.coreutils}/bin/date +%Y-%m-%d)
    ALL_BLOCKS=$(${SSH} ${CCUSAGE} blocks --json --token-limit max 2>/dev/null) || true
    ACTIVE_COST=$(echo "$ALL_BLOCKS" | ${JQ} -r '(.blocks[] | select(.isActive == true) | .costUSD) // empty' 2>/dev/null) || true
    TODAY_BLOCKS_COST=$(echo "$ALL_BLOCKS" | ${JQ} -r --arg today "$TODAY_DATE" \
      '[.blocks[] | select(.startTime | startswith($today)) | .costUSD] | add // 0' 2>/dev/null) || true
    if [ -n "$ACTIVE_COST" ]; then
      END_CLEAN=$(echo "$ALL_BLOCKS" | ${JQ} -r '.blocks[] | select(.isActive == true) | .endTime | split(".")[0] + "Z"')
      END_EPOCH=$(${pkgs.coreutils}/bin/date -d "$END_CLEAN" +%s)
      {
        echo "# HELP ccusage_block_token_percent_used Percent of 5h token limit used"
        echo "# TYPE ccusage_block_token_percent_used gauge"
        echo "$ALL_BLOCKS" | ${JQ} -r '.blocks[] | select(.isActive == true) | "ccusage_block_token_percent_used \(.tokenLimitStatus.percentUsed)"'

        echo "# HELP ccusage_block_end_timestamp Unix timestamp when current block ends"
        echo "# TYPE ccusage_block_end_timestamp gauge"
        echo "ccusage_block_end_timestamp $END_EPOCH"
      } | ${CURL} --silent --data-binary @- "$PUSHGATEWAY/metrics/job/ccusage-block"
    else
      ${CURL} --silent -X DELETE "$PUSHGATEWAY/metrics/job/ccusage-block" || true
    fi

    # --- weekly ---
    WEEKLY=$(${SSH} ${CCUSAGE} weekly --json 2>/dev/null) || true
    if [ -n "$WEEKLY" ]; then
      {
        echo "# HELP ccusage_current_week_cost_usd Current week cost all models in USD"
        echo "# TYPE ccusage_current_week_cost_usd gauge"
        echo "$WEEKLY" | ${JQ} -r '"ccusage_current_week_cost_usd \(.weekly | last | .totalCost)"'

        echo "# HELP ccusage_current_week_sonnet_cost_usd Current week Sonnet cost in USD"
        echo "# TYPE ccusage_current_week_sonnet_cost_usd gauge"
        echo "$WEEKLY" | ${JQ} -r '"ccusage_current_week_sonnet_cost_usd \(.weekly | last | .modelBreakdowns | map(select(.modelName | test("sonnet"))) | map(.cost) | add // 0)"'
      } | ${CURL} --silent --data-binary @- "$PUSHGATEWAY/metrics/job/ccusage-weekly"
    fi

    # --- period totals (7d, 30d): daily for past days + all today's blocks (includes active session) ---
    TODAY_COST=''${TODAY_BLOCKS_COST:-0}
    {
      echo "# HELP ccusage_period_cost_usd Cost over recent periods in USD"
      echo "# TYPE ccusage_period_cost_usd gauge"
      NOW=$(${pkgs.coreutils}/bin/date +%s)
      echo "$DAILY" | ${JQ} -r --argjson now "$NOW" --arg today "$TODAY_DATE" --argjson today_cost "$TODAY_COST" '
        ([.daily[] | select((.date | strptime("%Y-%m-%d") | mktime) > ($now - 86400 * 7) and .date != $today) | .totalCost] | add // 0) + $today_cost |
        "ccusage_period_cost_usd{period=\"7d\"} \(.)"
      '
      echo "$DAILY" | ${JQ} -r --argjson now "$NOW" --arg today "$TODAY_DATE" --argjson today_cost "$TODAY_COST" '
        ([.daily[] | select((.date | strptime("%Y-%m-%d") | mktime) > ($now - 86400 * 30) and .date != $today) | .totalCost] | add // 0) + $today_cost |
        "ccusage_period_cost_usd{period=\"30d\"} \(.)"
      '
    } | ${CURL} --silent --data-binary @- "$PUSHGATEWAY/metrics/job/ccusage-periods"
  '';
in
{
  imports = [
    ./modules/home-manager.nix
    ./modules/common.nix
    ./modules/nvim/neovim.nix
    ./modules/zsh.nix
    ./modules/tmux.nix

    ./modules/atuin.nix
    ./modules/kitty.nix
    ./modules/starship.nix
    ./modules/pw-play-wrapper.nix
    ./modules/ai.nix
  ];

  home = {
    username = "flakm";
    homeDirectory = "/home/flakm";
    stateVersion = "23.05";
  };

  systemd.user.services.ccusage-push = {
    Unit.Description = "Push ccusage daily stats to Prometheus Pushgateway";
    Service = {
      Type = "oneshot";
      ExecStart = "${ccusage-push}";
    };
  };

  systemd.user.timers.ccusage-push = {
    Unit.Description = "Run ccusage-push every 2 minutes";
    Timer = {
      OnBootSec = "1min";
      OnUnitActiveSec = "2min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
