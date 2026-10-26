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
  hasGithubToken = lib.hasInfix "github_token:" secretsFile;
in
{
  # The agent's unit tests + lint run as part of the system build, so a broken
  # change fails the deploy instead of reaching the odroid.
  system.checks = [
    inputs."coralogix-private".checks.${pkgs.stdenv.hostPlatform.system}.hermes-agent-tests
  ];

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
      # HTTP API bearer token (the TUI/CLI and the amd-pc bridge use it).
      HERMES_API_TOKEN_FILE = config.sops.secrets.hermes_api_token.path;
      # Vikunja API token: project 26 (Coralogix) + 27 (private week).
      VIKUNJA_API_TOKEN_FILE = config.sops.secrets.hermes_vikunja_token.path;
      # Jira Cloud API: issue refresh (tracking) and on-demand issue creation.
      JIRA_BASE_URL = "https://coralogix.atlassian.net";
      JIRA_EMAIL = "maciej.flak@coralogix.com";
      JIRA_TOKEN_FILE = config.sops.secrets.jira_coralogix_token.path;
      # Share the machine's nix cache (codex gets it as a writable root, see
      # codex_base_cmd) so `nix run` reuses what is already fetched.
      XDG_CACHE_HOME = "/home/flakm/.cache";
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
    } // lib.optionalAttrs hasGithubToken {
      GITHUB_TOKEN_FILE = config.sops.secrets.github_token.path;
    } // lib.optionalAttrs (hasTelegramBotToken && hasTelegramChatId) {
      # Kept for a quick fallback; the Telegram client stays disabled below.
      TELEGRAM_BOT_TOKEN_FILE = config.sops.secrets.hermes_telegram_bot_token.path;
      TELEGRAM_CHAT_ID_FILE = config.sops.secrets.hermes_telegram_chat_id.path;
    };
    path = [
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode2
      inputs.cx-cli.packages.${pkgs.stdenv.hostPlatform.system}.default
      pkgs.sqlite
      pkgs.gh
      # `nix run` for tools that are not worth pinning into PATH. The codex
      # sandbox keeps the home directory read-only, so the cache lives in /tmp
      # (XDG_CACHE_HOME below) or nix cannot write its flake registry.
      pkgs.nix
      # remote_exec: ssh to amd-pc for heavy builds; git for its known_hosts.
      pkgs.openssh
    ];
    settings = {
      agent = {
        name = "hermes";
        provider = "codex";
        model = "gpt-6.1-sol";
        # When codex credits/quota run out, fall back: Go subscription first
        # (reliable), then the free Zen tier as a backstop.
        # OpenCode's free Zen tier answers 403 FreeTierError from this network
        # ("abusive traffic from this IP"), so it is not in the chain at all.
        fallbacks = [
          {
            provider = "opencode";
            model = "opencode-go/deepseek-v4.1-flash";
          }
        ];
        # Fast model for summaries and drafts (flat-rate Go subscription);
        # the free tier is unavailable here.
        tasks = {
          draft = {
            provider = "opencode";
            model = "opencode-go/deepseek-v4.1-flash";
          };
          summary = {
            provider = "opencode";
            model = "opencode-go/deepseek-v4.1-flash";
          };
          # Quick answers: same fast model, no tools. Codex is reserved for
          # `deep:` / `hermes ask --deep` and automatic bumps.
          askFast = {
            provider = "opencode";
            model = "opencode-go/deepseek-v4.1-flash";
          };
        };
        # Answer from a state snapshot by default; the fast answer asks for a
        # bump when it needs live tools.
        fastAsk = {
          enable = true;
          contextThreads = 12;
          maxContextChars = 6000;
          timeoutSeconds = 30;
        };
        contextCacheSeconds = 300; # cache control-thread context + searches
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
        interestKeywords = [
          # Maciej's area: auth, identity, permissions, sessions.
          # These widen the cheap heuristic gate so relevant threads reach the
          # model instead of being dropped before review.
          "sso"
          "saml"
          "scim"
          "mfa"
          "login"
          "authn"
          "authz"
          "authentication"
          "authorization"
          "permissions"
          "identity"
          "sts"
          "session"
          "rollback"
          "security"
          "customer"
        ];
        memoryDir = "/home/flakm/.local/share/hermes-agent/memory";
        memoryMaxChars = 6000;
        # Freshest threads first each cycle; the rest rotate slowly.
        # 25 slots keeps a ~140-thread queue under ~7 minutes per rotation.
        followedRefreshBatchSize = 25;
        followedRefreshBudgetSeconds = 90;
        followedHotWindowSeconds = 21600; # 6h
        followedMaxNewMessages = 200;
        # Background PR summaries: someone asks for a review -> fetch the PR
        # with gh, summarise the change, reply in the card's thread.
        prSummary = {
          enable = true;
          orgs = [ "coralogix" ];
          maxDiffChars = 12000;
          cooldownSeconds = 21600; # re-summarise the same PR at most every 6h
          timeoutSeconds = 180;
          pollSeconds = 20;
        };
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
        # Follow-up tracking: per-thread cadence, "still waiting" reminders,
        # PR/Jira refresh. See modules/hermes-agent/PLATFORM.md.
        tracking = {
          enable = true;
          defaultReminderSeconds = 86400; # daily nudge when nothing moves
          minReminderSeconds = 900;
          maxRemindersPerCycle = 5;
          quietHours = [ 22 8 ];
          timezone = "Europe/Warsaw";
          prRefreshSeconds = 1800;
          jiraRefreshSeconds = 1800;
          # Reviews expire after two quiet days, anything else after four;
          # merged/closed PRs close immediately. Starred threads survive.
          autoClose = {
            enable = true;
            staleDays = 4;
            reviewDays = 2;
            mergedPrs = true;
            keepImportant = true;
          };
        };
        # HTTP API for the amd-pc TUI/CLI and the notification bridge.
        api = {
          enable = true;
          port = 8790;
        };
        # Mirror tracked work threads into "Coralogix - pilne" and create
        # personal tasks from natural language.
        vikunja = {
          enable = true;
          url = "http://127.0.0.1:3456";
          projectId = 26;
          personalProjectId = 27;
          label = "hermes";
          syncSeconds = 300;
        };
        # Jira: create issues on demand ("utwórz jira ticket …"). The token
        # comes from JIRA_TOKEN_FILE; the health card reports a rejected token.
        jira = {
          enable = true;
          baseUrl = "https://coralogix.atlassian.net";
          email = "maciej.flak@coralogix.com";
          tokenFile = config.sops.secrets.jira_coralogix_token.path;
          project = "CX";
          issueType = "Task";
          labels = [ "hermes" ];
        };
        # Heavy commands run on amd-pc when it is reachable.
        remote = {
          enable = true;
          host = "192.168.0.249";
          user = "flakm";
          sshKeyFile = config.sops.secrets.hermes_remote_ssh_key.path;
          workdir = "/tmp/hermes-remote";
          timeoutSeconds = 900;
          offload = [
            "nix build"
            "nix run"
            "nix develop"
            "cargo build"
            "cargo test"
            "pytest"
          ];
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
        notifiedDays = 14;
        threadDays = 90;
        # Matches slack.threadLookback: older threads cannot be re-discovered
        # from channel history anyway, and they were 92% of the refresh queue.
        subscriptionDays = 14;
        followedFailureLimit = 3;
      };
      observability = {
        heartbeatFile = "/var/lib/hermes-agent/heartbeat";
        metricsFile = "/var/lib/hermes-agent/metrics.prom";
        statusDir = "/var/www/hermes";
        usageFile = "/var/lib/hermes-agent/usage.json";
        # opencode keeps per-session tokens/cost here; Hermes reads it back.
        opencodeDb = "/home/flakm/.local/share/opencode/opencode.db";
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
          channel = null; # explicit channel id, if you have one
          channelName = "general"; # Hermes posts here (created/found by name)
          approverUserId = null; # DM fallback when the channel is unavailable
          commandsEnabled = true;
        };
        includeCollectedContext = false;
      };
    };
    healthcheck = {
      enable = true;
      onCalendar = "*-*-* 08:00:00";
    };
  };

  # Status page served from /var/www/hermes (written by the agent each cycle).
  systemd.tmpfiles.rules = [
    "d /var/www/hermes 0755 flakm users -"
  ];

  services.nginx.virtualHosts."hermes.house.flakm.com" = {
    useACMEHost = "house.flakm.com";
    forceSSL = true;
    root = "/var/www/hermes";
    # The agent's HTTP API (TUI/CLI + notification bridge). Token protected;
    # LAN/tailnet only. SSE needs buffering off and a long read timeout.
    locations."/api/" = {
      proxyPass = "http://127.0.0.1:8790";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_cache off;
        gzip off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        allow 192.168.0.0/16;
        allow 100.64.0.0/10;
        allow fd7a:115c:a1e0::/48;
        deny all;
      '';
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
  } // lib.optionalAttrs hasGithubToken {
    github_token = {
      owner = "flakm";
      group = "users";
      mode = "0400";
    };
  } // {
    # Hermes HTTP API (TUI/CLI + amd-pc notification bridge).
    hermes_api_token = {
      owner = "flakm";
      group = "users";
      mode = "0400";
      restartUnits = [ "hermes-agent.service" ];
    };
    # Vikunja API token for the tracked-thread mirror and natural-language tasks.
    hermes_vikunja_token = {
      owner = "flakm";
      group = "users";
      mode = "0400";
      restartUnits = [ "hermes-agent.service" ];
    };
    # Jira Cloud API token (shared with the tracking refresh and the
    # on-demand issue creation). Rotate at id.atlassian.com if it is rejected.
    jira_coralogix_token = {
      owner = "flakm";
      group = "users";
      mode = "0400";
      restartUnits = [ "hermes-agent.service" ];
    };
    # Key used for remote jobs (and as a nix build machine) on amd-pc.
    hermes_remote_ssh_key = {
      owner = "flakm";
      group = "users";
      mode = "0400";
      restartUnits = [ "hermes-agent.service" ];
    };
  };
}
