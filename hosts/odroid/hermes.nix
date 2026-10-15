{ config, inputs, lib, pkgs, ... }:
let
  secretsFile = builtins.readFile ../../secrets/secrets.yaml;
  hasHermesSlackSecret = lib.hasInfix "hermes_slack_bot_token:" secretsFile;
  hasHermesSlackAppToken = lib.hasInfix "hermes_slack_app_token:" secretsFile;
  hasTelegramBotToken = lib.hasInfix "hermes_telegram_bot_token:" secretsFile;
  hasTelegramChatId = lib.hasInfix "hermes_telegram_chat_id:" secretsFile;

  # Control workspace: a separate Slack app that DMs Maciej and accepts
  # follow-up questions/commands about a thread. Gated on the secrets so the
  # build keeps working before the app is created (see hermes-control-setup.md).
  hasControlBotToken = lib.hasInfix "hermes_control_slack_bot_token:" secretsFile;
  hasControlAppToken = lib.hasInfix "hermes_control_slack_app_token:" secretsFile;
  hasControlUserId = lib.hasInfix "hermes_control_slack_user_id:" secretsFile;
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
    } // lib.optionalAttrs hasHermesSlackAppToken {
      SLACK_APP_TOKEN_FILE = config.sops.secrets.hermes_slack_app_token.path;
    } // lib.optionalAttrs hasControlBotToken {
      CONTROL_SLACK_BOT_TOKEN_FILE = config.sops.secrets.hermes_control_slack_bot_token.path;
    } // lib.optionalAttrs hasControlAppToken {
      CONTROL_SLACK_APP_TOKEN_FILE = config.sops.secrets.hermes_control_slack_app_token.path;
    } // lib.optionalAttrs hasControlUserId {
      CONTROL_SLACK_USER_ID_FILE = config.sops.secrets.hermes_control_slack_user_id.path;
    } // lib.optionalAttrs (hasTelegramBotToken && hasTelegramChatId) {
      # Kept for a quick fallback; the Telegram client stays disabled below.
      TELEGRAM_BOT_TOKEN_FILE = config.sops.secrets.hermes_telegram_bot_token.path;
      TELEGRAM_CHAT_ID_FILE = config.sops.secrets.hermes_telegram_chat_id.path;
    };
    path = [
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
      inputs.cx-cli.packages.${pkgs.stdenv.hostPlatform.system}.default
      pkgs.sqlite
    ];
    settings = {
      agent = {
        name = "hermes";
        provider = "codex";
        model = "gpt-6.1-sol";
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
        enrichContext = true;
        triage = {
          enable = true;
          provider = null;
          model = null;
        };
      };
      memory = {
        feedback = true;
        retrieval = true;
      };
      history = {
        # SQLite store of every thread Hermes has seen/decided/notified.
        # Defaults to <memoryDir>/history.db when path is null.
        enable = true;
        path = null;
      };
      maintenance = {
        enable = true;
        notifiedDays = 30;
        threadDays = 90;
        subscriptionDays = 60;
        followedFailureLimit = 3;
      };
      observability = {
        heartbeatFile = "/var/lib/hermes-agent/heartbeat";
        metricsFile = "/var/lib/hermes-agent/metrics.prom";
      };
      slack = {
        watchedChannels = [
          "C03K13XKV6G" # internal
          "C03KNEM5DCG" # interface
          "C0BBE5L48AU" # flakm-test
        ];
        pollIntervalSeconds = 65;
        maxMessageAgeSeconds = 900;
        maxDecisionsPerChannelPerPoll = 5;
        requireThreadParticipation = false;
        backfillOnStart = false;
        threadLookback = "2d";
        mode = "poll";
        socketMinIntervalSeconds = 5;
        rateLimitMaxSleepSeconds = 30;
      };
      escalation = {
        urgentChannels = [ ];
        interactive = true;
        priorityRouting = true;
        desktopNotifications = false;
        signal = {
          enable = false;
          account = "+48786816597";
          configDir = "/home/flakm/.local/share/signal-cli-hermes";
          noteToSelf = true;
          recipients = [ ];
        };
        telegram = {
          # Replaced by the control workspace below.
          enable = false;
          chatId = null;
        };
        slackControl = {
          # Requires a separate Slack app (hermes-control-setup.md).
          enable = hasControlBotToken;
          channel = null; # null -> DM the approver below
          approverUserId = null; # falls back to CONTROL_SLACK_USER_ID_FILE
          commandsEnabled = true;
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
    } // lib.optionalAttrs hasHermesSlackAppToken {
    hermes_slack_app_token = {
      owner = "flakm";
      group = "users";
      mode = "0400";
      restartUnits = [ "hermes-agent.service" ];
    };
  } // lib.optionalAttrs (hasTelegramBotToken && hasTelegramChatId) {
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
  } // lib.optionalAttrs hasControlBotToken {
    hermes_control_slack_bot_token = {
      owner = "flakm";
      group = "users";
      mode = "0400";
      restartUnits = [ "hermes-agent.service" ];
    };
  } // lib.optionalAttrs hasControlAppToken {
    hermes_control_slack_app_token = {
      owner = "flakm";
      group = "users";
      mode = "0400";
      restartUnits = [ "hermes-agent.service" ];
    };
  } // lib.optionalAttrs hasControlUserId {
    hermes_control_slack_user_id = {
      owner = "flakm";
      group = "users";
      mode = "0400";
      restartUnits = [ "hermes-agent.service" ];
    };
  };
}
