{ config, lib, pkgs, llm-agents-pkgs, ... }:
let
  # claude as launched inside herdr (shell panes and session restore, which runs
  # a bare `claude --resume <id>`): always skip permission prompts
  claudeInHerdr = pkgs.writeShellScriptBin "claude" ''
    case " $* " in
      *" --dangerously-skip-permissions "*) ;;
      *) set -- --dangerously-skip-permissions "$@" ;;
    esac
    export OTEL_RESOURCE_ATTRIBUTES="''${OTEL_RESOURCE_ATTRIBUTES:-project.name=$(basename "$PWD"),project.path=$PWD}"
    exec ${llm-agents-pkgs.claude-code}/bin/claude "$@"
  '';
  herdr = pkgs.symlinkJoin {
    name = "herdr-${llm-agents-pkgs.herdr.version}";
    paths = [ llm-agents-pkgs.herdr ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = "wrapProgram $out/bin/herdr --prefix PATH : ${claudeInHerdr}/bin";
  };
  # Generate herdr's claude SessionStart hook at build time; ~/.claude/settings.json
  # is nix-managed so `herdr integration install claude` can't edit it at runtime.
  claudeHook = pkgs.runCommand "herdr-claude-hook" { } ''
    mkdir -p $out
    echo '{}' > $out/settings.json
    CLAUDE_CONFIG_DIR=$out HOME=$TMPDIR ${herdr}/bin/herdr integration install claude >/dev/null
  '';
  # herdr only tracks agents in its own panes, so move live claude sessions
  # (from tmux/kitty) into herdr by stopping them and resuming the same session.
  herdrAdopt = pkgs.writeShellApplication {
    name = "herdr-adopt";
    runtimeInputs = [ herdr pkgs.jq pkgs.procps pkgs.coreutils ];
    text = ''
      usage() { echo "usage: herdr-adopt [--apply] [--include-busy]  (dry-run by default)"; }
      apply=0 busy=0
      for a; do
        case $a in
          --apply) apply=1 ;;
          --include-busy) busy=1 ;;
          -h|--help) usage; exit 0 ;;
          *) usage >&2; exit 1 ;;
        esac
      done

      is_ancestor() {
        local p=$$
        while [ "$p" -gt 1 ]; do
          [ "$p" = "$1" ] && return 0
          p=$(ps -o ppid= -p "$p" | tr -d ' ')
        done
        return 1
      }

      # original argv minus session selectors
      resume_args() {
        local skip=0 out=() argv=()
        mapfile -d "" argv < "/proc/$1/cmdline"
        for x in "''${argv[@]:1}"; do
          if [ "$skip" = 1 ]; then
            skip=0
            [[ $x == -* ]] || continue
          fi
          case $x in
            --resume|-r|--session-id) skip=1 ;;
            --continue|-c|--resume=*|--session-id=*) ;;
            *) out+=("$x") ;;
          esac
        done
        [ ''${#out[@]} -eq 0 ] || printf '%q ' "''${out[@]}"
      }

      declare -A ws
      for f in "$HOME"/.claude/sessions/*.json; do
        [ -e "$f" ] || continue
        IFS=$'\t' read -r pid sid cwd status name kind tmux < <(jq -r '[.pid, .sessionId, .cwd, .status, (.name // ""), .kind, (.tmux // "" | split(":")[0])] | @tsv' "$f")
        [ "$kind" = interactive ] || continue
        kill -0 "$pid" 2>/dev/null || continue
        [[ $(cat "/proc/$pid/comm") == *claude* ]] || continue
        tr '\0' '\n' < "/proc/$pid/environ" | grep -qx HERDR_ENV=1 && continue
        name=''${name:-''${sid:0:8}}
        if is_ancestor "$pid"; then echo "skip  $name (this shell's session)"; continue; fi
        if [ "$status" = busy ] && [ "$busy" = 0 ]; then echo "skip  $name (busy)"; continue; fi
        echo "adopt $name  $cwd''${tmux:+  (tmux: $tmux)}"
        [ "$apply" = 1 ] || continue

        args=$(resume_args "$pid")
        kill -TERM "$pid"
        for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
        if kill -0 "$pid" 2>/dev/null; then echo "  failed to stop pid $pid" >&2; continue; fi

        # tmux session -> herdr workspace (named after it); tabs are named by herdr-autoname
        key=''${tmux:-$cwd}
        if [ -z "''${ws[$key]:-}" ]; then
          r=$(herdr workspace create --cwd "$cwd" ''${tmux:+--label "$tmux"} --no-focus)
          ws[$key]=$(jq -r .result.workspace.workspace_id <<<"$r")
        else
          r=$(herdr tab create --workspace "''${ws[$key]}" --cwd "$cwd" --no-focus)
        fi
        herdr pane run "$(jq -r .result.root_pane.pane_id <<<"$r")" "claude $args--resume $sid" >/dev/null
      done
      [ "$apply" = 1 ] || echo "dry run; pass --apply to move these into herdr"
    '';
  };
  # herdr's opencode plugins (session resume + lifecycle state); none touch opencode.json
  opencodeIntegration = pkgs.runCommand "herdr-opencode-integration" { } ''
    mkdir -p $TMPDIR/.config/opencode $out
    HOME=$TMPDIR ${herdr}/bin/herdr integration install opencode >/dev/null
    cp -r $TMPDIR/.config/opencode $out/
  '';

  herdrAutoname = pkgs.writers.writePython3Bin "herdr-autoname"
    {
      flakeIgnore = [ "E501" ];
    }
    (builtins.readFile ./herdr-autoname.py);
  cfg = config.herdr;
in
{
  imports = [ ./herdr-nvim.nix ];

  options.herdr = {
    sidebarWidth = lib.mkOption { type = lib.types.int; default = 40; };
    sidebarMaxWidth = lib.mkOption { type = lib.types.int; default = 60; };
  };

  config = {
    home.packages = [ herdr herdrAdopt herdrAutoname ];

    systemd.user.services.herdr-autoname = lib.mkIf pkgs.stdenv.isLinux {
      Unit.Description = "Rename herdr tabs after their pane title";
      Service = {
        ExecStart = "${herdrAutoname}/bin/herdr-autoname";
        Restart = "always";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    launchd.agents.herdr-autoname = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = {
        ProgramArguments = [ "${herdrAutoname}/bin/herdr-autoname" ];
        KeepAlive = true;
        RunAtLoad = true;
      };
    };

    # ~/.codex/config.toml is codex-mutated, so let herdr's installer merge into it
    home.activation.herdrCodexIntegration = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -d "$HOME/.codex" ] && ! ${herdr}/bin/herdr integration status 2>/dev/null | grep -q '^codex: current'; then
        run ${herdr}/bin/herdr integration install codex >/dev/null
      fi
    '';

    home.file.".claude/hooks/herdr-agent-state.sh".source = "${claudeHook}/hooks/herdr-agent-state.sh";

    xdg.configFile."opencode/plugins/herdr-agent-state.js".source = "${opencodeIntegration}/opencode/plugins/herdr-agent-state.js";
    xdg.configFile."opencode/herdr-tui-session.js".source = "${opencodeIntegration}/opencode/herdr-tui-session.js";
    xdg.configFile."opencode/herdr-opencode/tui.js".source = "${opencodeIntegration}/opencode/herdr-opencode/tui.js";
    xdg.configFile."opencode/tui.jsonc".source = "${opencodeIntegration}/opencode/tui.jsonc";

    # Mirrors tmux.nix: same prefix, splits, hjkl, reload, vi copy mode, status-right.
    xdg.configFile."herdr/config.toml".text = ''
      onboarding = false

      [theme]
      # follow kitty's ANSI palette so dark/light/sunlight switching carries over
      name = "terminal"

      [terminal]
      default_shell = "${pkgs.zsh}/bin/zsh"
      new_cwd = "follow"

      [update]
      version_check = false

      [keys]
      prefix = "ctrl+b"
      split_vertical = ["prefix+v", "prefix+|", "prefix+percent"]
      split_horizontal = ["prefix+minus", "prefix+double_quote"]
      goto = ["prefix+g", "ctrl+l"]
      last_pane = "prefix+;"
      reload_config = "prefix+shift+r"
      # walk agents in sidebar order (priority: blocked first); prefix+o only works while a toast is up
      next_agent = "prefix+a"
      previous_agent = "prefix+shift+a"
      # navigate mode (prefix+w): j/k walk workspaces like a list, ctrl+j/k move panes
      navigate_workspace_up = ["k", "up"]
      navigate_workspace_down = ["j", "down"]
      navigate_pane_up = "ctrl+k"
      navigate_pane_down = "ctrl+j"

      [[keys.command]]
      key = "prefix+shift+e"
      type = "plugin_action"
      command = "chmarax.herdr-nvim.toggle"
      description = "nvim sidebar"

      [[keys.command]]
      key = "prefix+shift+o"
      type = "plugin_action"
      command = "chmarax.herdr-nvim.pick-file"
      description = "open file from agent output"

      [ui]
      sidebar_width = ${toString cfg.sidebarWidth}
      sidebar_max_width = ${toString cfg.sidebarMaxWidth}
      prompt_new_tab_name = false
      agent_panel_sort = "priority"
      pane_outer_borders = false
      pane_gaps = false
      tab_bar_position = "bottom"
      tab_bar_right = [
        { type = "hostname" },
        { type = "datetime", format = "%H:%M" },
      ]

      # in-app toast when a background agent finishes or blocks; prefix+o jumps to it
      [ui.toast]
      delivery = "herdr"
    '';
  };
}
