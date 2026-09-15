{ config, inputs, lib, pkgs, ... }:
let
  hasHermesSlackSecret = lib.hasInfix "hermes_slack_bot_token:" (builtins.readFile ../../secrets/secrets.yaml);
in
{
  services.hermes-agent = {
    enable = true;
    package = inputs.coralogix-private.packages.${pkgs.stdenv.hostPlatform.system}.hermes-agent;
    user = "flakm";
    group = "users";
    createUser = false;
    stateDir = "/var/lib/hermes-agent";
    environment = {
      CODEX_HOME = "/home/flakm/.codex";
      CX_READ_ONLY = "1";
      HOME = "/home/flakm";
    } // lib.optionalAttrs hasHermesSlackSecret {
      SLACK_BOT_TOKEN_FILE = config.sops.secrets.hermes_slack_bot_token.path;
    } // {
      TELEGRAM_BOT_TOKEN_FILE = config.sops.secrets.hermes_telegram_bot_token.path;
      TELEGRAM_CHAT_ID_FILE = config.sops.secrets.hermes_telegram_chat_id.path;
    };
    path = [
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
      inputs.cx-cli.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
    settings = {
      agent = {
        name = "hermes";
        provider = "codex";
        model = "gpt-5.5";
        decisionPolicy = builtins.readFile ./hermes-interest.md;
        ignoredAuthorUserIds = [
          "self"
          "U082RB1R9U4" # flakm
        ];
        ignoredAuthorUserIdsByChannel = {
          "C0BBE5L48AU" = [ ]; # flakm-test
        };
        importantMentions = [
          "<@U082RB1R9U4>"
          "rnd-vertex-aaa"
        ];
        interestKeywords = [ ];
        memoryDir = "/home/flakm/.local/share/hermes-agent/memory";
        memoryMaxChars = 6000;
        followedRefreshBatchSize = 10;
        followedRefreshBudgetSeconds = 60;
        discoveryBudgetSeconds = 60;
        workingDirectory = "/home/flakm/programming/coralogix/aaa-daily-reporter";
        contextPaths = [
          "/home/flakm/programming/coralogix/aaa-daily-reporter"
          "/home/flakm/programming/coralogix/cx-cli"
          "${inputs.cx-cli.packages.${pkgs.stdenv.hostPlatform.system}.skills}"
        ];
        contextInstructions = ''
          Use aaa-daily-reporter as Maciej's AAA operational map: service inventory, known-noise context, custom checks, login-events privacy rules, auditor lag checks, blocked-team checks, and daily health-report semantics.

          Use cx-cli as the read-only observability tool. The `cx` binary is on PATH. Prefer `cx schema` for command discovery and the skills under cx-cli/skills for query workflows. Read-only commands such as `cx logs`, `cx spans`, `cx metrics`, `cx search-fields`, `cx alerts list/get/events`, `cx incidents list/get`, and `cx iam ... list/get/search` are allowed when a Slack thread looks investigation-worthy.

          Never run cx write/risky operations. Never pass `--yes`. Keep any live telemetry query narrow: recent time windows, low limits, and `-o agents` or `-o json`. Do not query telemetry for routine PR links, greetings, or already-clear Slack threads; use the repos/skills mostly as background unless the thread mentions incidents, SSO/login/authz/permissions failures, customer impact, production/staging errors, audit-log delivery, blocked teams, Kafka lag, or requests for investigation.

          When using AAA reporter checks, follow their privacy rules. In particular, login-events checks must not inspect actor/client fields and should aggregate by safe dimensions only.
        '';
      };
      slack = {
        watchedChannels = [
          "C03K13XKV6G" # internal
          "C03KNEM5DCG" # interface
          "C0BBE5L48AU" # flakm-test
        ];
        pollIntervalSeconds = 65;
        maxDecisionsPerChannelPerPoll = 5;
        requireThreadParticipation = false;
        backfillOnStart = false;
        threadLookback = "2d";
      };
      escalation = {
        urgentChannels = [ ];
        desktopNotifications = false;
        signal = {
          enable = false;
          account = "+48786816597";
          configDir = "/home/flakm/.local/share/signal-cli-hermes";
          noteToSelf = true;
          recipients = [ ];
        };
        telegram = {
          enable = true;
          chatId = null;
        };
        includeCollectedContext = false;
      };
    };
  };

  sops.secrets = lib.optionalAttrs hasHermesSlackSecret
    {
      hermes_slack_bot_token = {
        owner = "flakm";
        group = "users";
        mode = "0400";
        restartUnits = [ "hermes-agent.service" ];
      };
    } // {
    hermes_telegram_bot_token = {
      owner = "flakm";
      group = "users";
      mode = "0400";
      restartUnits = [ "hermes-agent.service" ];
    };
    hermes_telegram_chat_id = {
      owner = "flakm";
      group = "users";
      mode = "0400";
      restartUnits = [ "hermes-agent.service" ];
    };
  };
}
