# NixOS MicroVM guest — "clawd".
# SSH: ssh clawd  (host resolves clawd → 192.168.100.10, User flakm)
# Reachable at 192.168.100.10 from the host.
{ lib, pkgs, ... }:
let
  openclaw = pkgs.callPackage ./openclaw.nix {};
  webhookPort = 8788;
  clawdZshrc = ''
    bindkey "^[[H" beginning-of-line
    bindkey "^[[F" end-of-line
    bindkey "^[[1;5C" forward-word
    bindkey "^[[1;5D" backward-word
    bindkey "^[[1;3C" forward-word
    bindkey "^[[1;3D" backward-word

    export HISTFILE="$HOME/.zsh_history"
    export ATUIN_NOBIND="true"

    eval "$(starship init zsh)"
    eval "$(zoxide init zsh)"
    eval "$(atuin init zsh)"

    bindkey -M viins -r '^R'
    bindkey -M viins '^R' atuin-search-viins
    bindkey -M vicmd -r '^R'
    bindkey -M vicmd '^R' atuin-search-vicmd
    bindkey '^R' atuin-search-viins
    bindkey '^[[A' atuin-up-search-viins
    bindkey '^[OA' atuin-up-search-viins
    bindkey -M viins '^[[A' atuin-up-search-viins
    bindkey -M viins '^[OA' atuin-up-search-viins
    bindkey -M vicmd '^[[A' atuin-up-search-viins
    bindkey -M vicmd '^[OA' atuin-up-search-viins

    function zvm_config() {
      ZVM_LAZY_KEYBINDINGS=false
    }

    function zvm_after_init() {
      true
    }

    source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh

    alias ls='eza'
    alias ll='eza -l'
    alias vim='nvim'
    alias vi='vi'
    alias k='kubectl'

    [ -f "$HOME/.openclaw/secrets/github-env" ] && source "$HOME/.openclaw/secrets/github-env"
    [ -f "$HOME/.openclaw/secrets/jira-env" ] && source "$HOME/.openclaw/secrets/jira-env"

    source ~/.zshrc_local 2>/dev/null || true
    source ~/.jfrog.env 2>/dev/null || true
    source ~/.sdkman/bin/sdkman-init.sh 2>/dev/null || true
  '';
  clawdStarshipToml = ''
    add_newline = false

    [aws]
    disabled = true

    [gcloud]
    disabled = true

    [python]
    disabled = true

    [directory]
    read_only = "[ro]"

    [hostname]
    ssh_only = true
  '';
  clawdAtuinToml = ''
    auto_sync = true
    ctrl_n_shortcuts = true
    filter_mode_shell_up_key_binding = "session"
    keymap_mode = "vim-insert"

    [sync]
    records = true
  '';
in {

  microvm = {
    hypervisor = "qemu";
    vcpu = 2;
    mem = 4096;

    interfaces = [{
      type = "bridge";
      id = "vm-clawd";
      mac = "02:00:00:00:00:01";
      bridge = "microbr0";
    }];

    volumes = [{
      mountPoint = "/var";
      image = "clawd-var.img";
      size = 4096;
    }];
  };

  networking = {
    hostName = "clawd";
    hosts."192.168.0.102" = [ "nextcloud.house.flakm.com" ];
    useDHCP = false;
    usePredictableInterfaceNames = false;
    interfaces.eth0.ipv4.addresses = [{
      address = "192.168.100.10";
      prefixLength = 24;
    }];
    defaultGateway = {
      address = "192.168.100.1";
      interface = "eth0";
    };
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 webhookPort ];
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  programs.zsh.enable = true;
  programs.zsh.enableCompletion = true;
  programs.zsh.autosuggestions.enable = true;
  programs.zsh.syntaxHighlighting.enable = true;

  security.sudo.extraRules = [{
    users = [ "flakm" ];
    commands = [{ command = "ALL"; options = [ "NOPASSWD" ]; }];
  }];

  users.users.flakm = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDh6bzSNqVZ1Ba0Uyp/EqThvDdbaAjsJ4GvYN40f/p9Wl4LcW/MQP8EYLvBTqTluAwRXqFa6fVpa0Y9Hq4kyNG62HiMoQRjujt6d3b+GU/pq7NN8+Oed9rCF6TxhtLdcvJWHTbcq9qIGs2s3eYDlMy+9koTEJ7Jnux0eGxObUaGteQUS1cOZ5k9PQg+WX5ncWa3QvqJNxx446+OzVoHgzZytvXeJMg91gKN9wAhKgfibJ4SpQYDHYcTrOILm7DLVghrcU2aFqLKVTrHSWSugfLkqeorRadHckRDr2VUzm5eXjcs4ESjrG6viKMKmlF1wxHoBrtfKzJ1nR8TGWWeH9NwXJtQ+qRzAhnQaHZyCZ6q4HvPlxxXOmgE+JuU6BCt6YPXAmNEMdMhkqYis4xSzxwWHvko79NnKY72pOIS2GgS6Xon0OxLOJ0mb66yhhZB4hUBb02CpvCMlKSLtvnS+2IcSGeSQBnwBw/wgp1uhr9ieUO/wY5K78w2kYFhR6Iet55gutbikSqDgxzTmuX3Mkjq0L/MVUIRAdmOysrR2Lxlk692IrNYTtUflQLsSfzrp6VQIKPxjfrdFhHIfbPoUdfMf+H06tfwkGONgcej56/fDjFbaHouZ357wcuwDsuMGNRCdyW7QyBXF/Wi28nPq/KSeOdCy+q9KDuOYsX9n/5Rsw== flakm"
    ];
  };

  environment.defaultPackages = lib.mkForce [];
  environment.systemPackages = with pkgs; [
    atuin
    claude-code
    curl
    eza
    gh
    git
    jira-cli-go
    jq
    litellm
    openclaw
    starship
    zoxide
    zsh
    zsh-vi-mode
  ];

  services.xserver.enable = lib.mkDefault false;
  documentation.enable = false;
  documentation.nixos.enable = false;

  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
  };

  # Persist user state across rootfs resets: /home/flakm is a symlink into /var.
  environment.variables.OPENCLAW_CONFIG_PATH = "/var/home/flakm/.openclaw/openclaw.json";

  # Seed the writable state dir on every boot.
  # Runtime-only state like auth stays in /var, while declarative keys from /etc override it.
  systemd.services.openclaw-seed-config = {
    description = "Seed OpenClaw config to writable state dir";
    requiredBy = [ "openclaw-gateway.service" ];
    before = [ "openclaw-gateway.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "flakm";
    };
    path = [ pkgs.coreutils pkgs.jq ];
    script = ''
      CONFIG=/var/home/flakm/.openclaw/openclaw.json
      ETC=/etc/openclaw/openclaw.json
      HOME_DIR=/var/home/flakm
      mkdir -p "$HOME_DIR" "$HOME_DIR/.openclaw/secrets" "$HOME_DIR/.openclaw/skills" "$HOME_DIR/.config/atuin" "$HOME_DIR/.local/share/atuin"

      # Sync declarative skills into the writable state dir
      cp -rT ${./skills} "$HOME_DIR/.openclaw/skills"
      chmod -R u+rw "$HOME_DIR/.openclaw/skills"
      touch "$HOME_DIR/.bash_history"
      if [ ! -e "$HOME_DIR/.zsh_history" ]; then
        touch "$HOME_DIR/.zsh_history"
      fi

      cat > "$HOME_DIR/.zshrc" <<'ZSHEOF'
${clawdZshrc}
ZSHEOF
      chmod 600 "$HOME_DIR/.zshrc"

      cat > "$HOME_DIR/.config/starship.toml" <<'STARSHIPEOF'
${clawdStarshipToml}
STARSHIPEOF
      chmod 600 "$HOME_DIR/.config/starship.toml"

      cat > "$HOME_DIR/.config/atuin/config.toml" <<'ATUINEOF'
${clawdAtuinToml}
ATUINEOF
      chmod 600 "$HOME_DIR/.config/atuin/config.toml"

      # Merge config: preserve runtime auth/channels/commands, but let /etc override declarative keys.
      if [ -f "$CONFIG" ]; then
        jq -s '.[1] * .[0]' "$ETC" "$CONFIG" > "$CONFIG.tmp" \
          && mv "$CONFIG.tmp" "$CONFIG"
      else
        cp "$ETC" "$CONFIG"
      fi

      jq 'del(.agent, .channels.whatsapp)' "$CONFIG" > "$CONFIG.tmp" \
        && mv "$CONFIG.tmp" "$CONFIG"
      chmod 600 "$CONFIG"

      if [ -f /run/host-secrets/nextcloud_talk_bot_secret ]; then
        install -m 600 /run/host-secrets/nextcloud_talk_bot_secret \
          /var/home/flakm/.openclaw/secrets/nextcloud_talk_bot_secret
      fi

      if [ -f /run/host-secrets/github_token ]; then
        token=$(tr -d '\n' < /run/host-secrets/github_token)
        printf 'export GH_TOKEN=%s\nexport GITHUB_TOKEN=%s\n' "$token" "$token" \
          > /var/home/flakm/.openclaw/secrets/github-env
        chmod 600 /var/home/flakm/.openclaw/secrets/github-env
      fi

      if [ -f /run/host-secrets/jira_coralogix_token ]; then
        jira_token=$(tr -d '\n' < /run/host-secrets/jira_coralogix_token)
        printf 'export JIRA_API_TOKEN=%s\n' "$jira_token" \
          > /var/home/flakm/.openclaw/secrets/jira-env
        chmod 600 /var/home/flakm/.openclaw/secrets/jira-env
      fi

      # Seed jira CLI config
      mkdir -p "$HOME_DIR/.config/.jira"
      cat > "$HOME_DIR/.config/.jira/.config.yml" <<'JIRAEOF'
auth_type: basic
installation: Cloud
login: maciej.flak@coralogix.com
server: https://coralogix.atlassian.net
JIRAEOF
      chmod 600 "$HOME_DIR/.config/.jira/.config.yml"
    '';
  };

  services.openclaw-gateway = {
    enable = true;
    package = openclaw;
    user = "flakm";
    group = "users";
    createUser = false;
    stateDir = "/var/home/flakm/.openclaw";
    environment.OPENCLAW_CONFIG_PATH = "/var/home/flakm/.openclaw/openclaw.json";
    config.gateway.mode = "local";
    config.gateway.auth.mode = "none";
    config.agents.defaults.model.primary = "openai-codex/gpt-5.4";
    config.agents.defaults.model.fallbacks = [
      "anthropic/claude-sonnet-4-6"
      "anthropic/claude-haiku-4-5"
    ];
    config.secrets.providers.local = {
      source = "file";
      path = "/var/home/flakm/.openclaw/secrets/nextcloud_talk_bot_secret";
      mode = "singleValue";
    };
    config.channels."nextcloud-talk" = {
      enabled = true;
      baseUrl = "https://nextcloud.house.flakm.com";
      groupPolicy = "open";
      rooms."*".requireMention = false;
      botSecret = {
        source = "file";
        provider = "local";
        id = "value";
      };
      webhookPort = webhookPort;
      webhookPublicUrl = "http://192.168.0.249:${toString webhookPort}/nextcloud-talk-webhook";
    };
  };

  systemd.tmpfiles.rules = [
    "d  /var/home/flakm        0700 flakm users -"
    "d  /var/home/flakm/.config 0700 flakm users -"
    "d  /var/home/flakm/.local  0700 flakm users -"
    "d  /var/home/flakm/.local/share 0700 flakm users -"
    "L+ /home/flakm/.openclaw  -    -     -     - /var/home/flakm/.openclaw"
    "L+ /home/flakm/.gitconfig -    -     -     - /var/home/flakm/.gitconfig"
    "L+ /home/flakm/.config    -    -     -     - /var/home/flakm/.config"
    "L+ /home/flakm/.npm       -    -     -     - /var/home/flakm/.npm"
    "L+ /home/flakm/.local     -    -     -     - /var/home/flakm/.local"
    "L+ /home/flakm/.zshrc     -    -     -     - /var/home/flakm/.zshrc"
    "f  /var/home/flakm/.bash_history 0600 flakm users -"
    "f  /var/home/flakm/.zsh_history  0600 flakm users -"
  ];

  system.stateVersion = "25.11";
}
