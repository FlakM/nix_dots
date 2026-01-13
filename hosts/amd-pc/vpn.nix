# Pritunl VPN with split DNS for Kubernetes cluster.local
# Works without NetworkManager using systemd-resolved and udev rules
{ pkgs, lib, ... }:

{
  boot.kernelModules = [ "tun" ];

  # Enable the pritunl-client daemon (required for CLI to work)
  systemd.services.pritunl-client = {
    description = "Pritunl Client Daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.pritunl-client}/bin/pritunl-client-service";
      Restart = "always";
    };
  };

  # Enable systemd-resolved for split DNS
  services.resolved = {
    enable = true;
    dnssec = "allow-downgrade";
    domains = [ "~." ];
    # Use your AdGuard as fallback
    fallbackDns = [ "192.168.0.102" "1.1.1.1" ];
    extraConfig = ''
      DNSStubListener=yes
    '';
  };

  # Point /etc/resolv.conf to resolved
  networking.nameservers = [ "127.0.0.53" ];

  environment.systemPackages = with pkgs; [
    pritunl-client
    openvpn
    fzf
    jq

    (writeShellScriptBin "vpn-waybar" ''
      JQ="${jq}/bin/jq"
      PRITUNL=$(pritunl-client list --json 2>/dev/null)
      ACTIVE=$(echo "$PRITUNL" | $JQ -r '[.[] | select(.run_state == "Active")] | length')
      NAMES=$(echo "$PRITUNL" | $JQ -r '[.[] | select(.run_state == "Active") | .name | gsub("maciej.flak "; "") | gsub("[()]"; "")] | join(", ")')

      TS_ONLINE="false"
      if command -v tailscale &>/dev/null; then
        TS_ONLINE=$(tailscale status --json 2>/dev/null | $JQ -r '.Self.Online // false')
      fi

      if [ "$ACTIVE" -gt 0 ] && [ "$TS_ONLINE" = "true" ]; then
        CLASS="both"
        TEXT="󰌘 $NAMES + TS"
        TOOLTIP="Pritunl: $NAMES\nTailscale: connected"
      elif [ "$ACTIVE" -gt 0 ]; then
        CLASS="pritunl"
        TEXT="󰌘 $NAMES"
        TOOLTIP="Pritunl: $NAMES"
      elif [ "$TS_ONLINE" = "true" ]; then
        CLASS="tailscale"
        TEXT="󰒍 TS"
        TOOLTIP="Tailscale: connected"
      else
        CLASS="disconnected"
        TEXT="󰌙 VPN off"
        TOOLTIP="VPN: disconnected"
      fi

      printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$TEXT" "$TOOLTIP" "$CLASS"
    '')

    (writeShellScriptBin "vpn-menu" ''
      JQ="${jq}/bin/jq"

      PRITUNL=$(pritunl-client list --json 2>/dev/null)
      ACTIVE_PRITUNL=$(echo "$PRITUNL" | $JQ -r '.[] | select(.run_state == "Active") | "\(.id)|\(.name | gsub("maciej.flak "; "") | gsub("[()]"; ""))"')
      INACTIVE_PRITUNL=$(echo "$PRITUNL" | $JQ -r '.[] | select(.run_state == "Inactive") | "\(.id)|\(.name | gsub("maciej.flak "; "") | gsub("[()]"; ""))"')

      TS_ONLINE="false"
      if command -v tailscale &>/dev/null; then
        TS_ONLINE=$(tailscale status --json 2>/dev/null | $JQ -r '.Self.Online // false')
      fi

      MENU=""
      while IFS='|' read -r id name; do
        [ -n "$name" ] && MENU="󰌘 Disconnect: $name [pritunl:$id]"$'\n'"$MENU"
      done <<< "$ACTIVE_PRITUNL"

      if [ "$TS_ONLINE" = "true" ]; then
        MENU="󰒍 Disconnect: Tailscale [tailscale]"$'\n'"$MENU"
      fi

      while IFS='|' read -r id name; do
        [ -n "$name" ] && MENU="$MENU󰌘 Connect: $name [connect:$id]"$'\n'
      done <<< "$INACTIVE_PRITUNL"

      if [ "$TS_ONLINE" != "true" ]; then
        MENU="$MENU󰒍 Connect: Tailscale [ts-connect]"$'\n'
      fi

      MENU="$MENU Status [status]"

      SELECTION=$(printf "%s" "$MENU" | walker -d)
      [ -z "$SELECTION" ] && exit 0

      case "$SELECTION" in
        *"[pritunl:"*) ID=$(echo "$SELECTION" | sed 's/.*\[pritunl:\([^]]*\)\].*/\1/'); pritunl-client stop "$ID" ;;
        *"[tailscale]"*) sudo tailscale down ;;
        *"[connect:"*) ID=$(echo "$SELECTION" | sed 's/.*\[connect:\([^]]*\)\].*/\1/'); kitty -e bash -c "vpn connect $ID; echo; echo 'Press Enter to close'; read" ;;
        *"[ts-connect]"*) sudo tailscale up ;;
        *"[status]"*) kitty --hold -e vpn s ;;
      esac
    '')

    (writeShellScriptBin "vpn" ''
      set -e
      JQ="${jq}/bin/jq"
      FZF="${fzf}/bin/fzf"
      GREEN=$'\033[32m'
      RESET=$'\033[0m'

      get_profiles() {
        pritunl-client list --json 2>/dev/null | $JQ -r '.[] | "\(.id) \(.name | gsub("[()]"; "") | gsub("maciej.flak "; ""))"'
      }

      resolve_profile() {
        pritunl-client list --json 2>/dev/null | $JQ -r --arg q "$1" \
          '.[] | select(.id == $q or (.name | test($q; "i"))) | .id' | head -1
      }

      cmd_connect() {
        if [ -z "''${1:-}" ]; then
          SELECTION=$(get_profiles | $FZF --prompt="Select VPN: " --height=20 --reverse)
          [ -z "$SELECTION" ] && exit 0
          PROFILE_ID=$(echo "$SELECTION" | awk '{print $1}')
        else
          PROFILE_ID=$(resolve_profile "$1")
          if [ -z "$PROFILE_ID" ]; then
            echo "Profile not found: $1"
            get_profiles | awk '{$1=""; print substr($0,2)}'
            exit 1
          fi
        fi

        echo "Connecting to: $PROFILE_ID"
        pritunl-client start "$PROFILE_ID"

        echo "Waiting for VPN interface..."
        for i in $(seq 1 30); do
          IFACE=$(ip link show type tun 2>/dev/null | grep -oP 'tun\d+' | head -1)
          [ -n "$IFACE" ] && echo "VPN interface $IFACE is up" && break
          sleep 1
        done

        if [ -z "$IFACE" ]; then
          echo "ERROR: VPN interface not found after 30s"
          exit 1
        fi

        # Detect k8s DNS from service CIDR routes
        DNS_IP=$(ip route show dev "$IFACE" | grep -oP '(172\.20|101\.64|10\.96|10\.43)\.\d+\.\d+' | head -1 | sed 's/\.[0-9]*$/\.10/')
        DNS_IP="''${DNS_IP:-172.20.0.10}"
        echo "Configuring split DNS via $IFACE (DNS: $DNS_IP)"
        sudo resolvectl dns "$IFACE" "$DNS_IP"
        sudo resolvectl domain "$IFACE" "~cluster.local" "~svc.cluster.local"
        sudo resolvectl default-route "$IFACE" false
        echo ""
        resolvectl status "$IFACE"
      }

      cmd_disconnect() {
        get_active() {
          pritunl-client list --json 2>/dev/null | $JQ -r \
            '.[] | select(.run_state == "Active") | "\(.id) \(.name | gsub("[()]"; "") | gsub("maciej.flak "; ""))"'
        }

        if [ -z "''${1:-}" ]; then
          ACTIVE=$(get_active)
          if [ -z "$ACTIVE" ]; then
            echo "No active VPN connections"
            exit 0
          fi
          COUNT=$(echo "$ACTIVE" | wc -l)
          if [ "$COUNT" -eq 1 ]; then
            PROFILE_ID=$(echo "$ACTIVE" | awk '{print $1}')
          else
            SELECTION=$(echo "$ACTIVE" | $FZF --prompt="Disconnect: " --height=10 --reverse)
            [ -z "$SELECTION" ] && exit 0
            PROFILE_ID=$(echo "$SELECTION" | awk '{print $1}')
          fi
        else
          PROFILE_ID=$(resolve_profile "$1")
          [ -z "$PROFILE_ID" ] && echo "Profile not found: $1" && exit 1
        fi

        echo "Disconnecting: $PROFILE_ID"
        pritunl-client stop "$PROFILE_ID"
        echo "VPN disconnected"
      }

      cmd_status() {
        BOLD=$'\033[1m'
        DIM=$'\033[2m'
        DATA=$(pritunl-client list --json 2>/dev/null)

        printf "%s══ Pritunl ══%s\n" "$BOLD" "$RESET"
        ACTIVE=$(echo "$DATA" | $JQ -r '.[] | select(.run_state == "Active") | "\(.name)|\(.status)|\(.client_address)"')
        if [ -n "$ACTIVE" ]; then
          echo "$ACTIVE" | while IFS='|' read -r name status addr; do
            name=$(echo "$name" | sed 's/maciej.flak //; s/[()]//g')
            printf "  %s●%s %s%s%s  %s%s  %s%s\n" "$GREEN" "$RESET" "$BOLD" "$name" "$RESET" "$DIM" "$status" "$addr" "$RESET"
          done
        fi
        echo "$DATA" | $JQ -r '.[] | select(.run_state == "Inactive") | .name' | sed 's/maciej.flak //; s/[()]//g' | while read -r name; do
          printf "  %s○ %s%s\n" "$DIM" "$name" "$RESET"
        done

        if command -v tailscale &>/dev/null; then
          echo ""
          printf "%s══ Tailscale ══%s\n" "$BOLD" "$RESET"
          TS=$(tailscale status --json 2>/dev/null)
          if [ -n "$TS" ]; then
            SELF=$(echo "$TS" | $JQ -r '.Self.HostName // empty')
            IPS=$(echo "$TS" | $JQ -r '.Self.TailscaleIPs // [] | .[0]')
            ONLINE=$(echo "$TS" | $JQ -r '.Self.Online // false')
            if [ "$ONLINE" = "true" ]; then
              printf "  %s●%s %s%s%s  %s%s%s\n" "$GREEN" "$RESET" "$BOLD" "$SELF" "$RESET" "$DIM" "$IPS" "$RESET"
            else
              printf "  %s○ %s (offline)%s\n" "$DIM" "$SELF" "$RESET"
            fi
          fi
        fi

        echo ""
        printf "%s══ DNS ══%s\n" "$BOLD" "$RESET"
        for IFACE in $(ip link show type tun 2>/dev/null | grep -oP '(tun\d+|tailscale\d+)'); do
          DNS=$(resolvectl status "$IFACE" 2>/dev/null | grep "DNS Servers" | awk '{print $3}')
          DOMAINS=$(resolvectl status "$IFACE" 2>/dev/null | grep "DNS Domain" | cut -d: -f2 | xargs)
          if [ -n "$DNS" ]; then
            printf "  %s%s%s  %s → %s%s%s\n" "$BOLD" "$IFACE" "$RESET" "$DNS" "$DIM" "$DOMAINS" "$RESET"
          fi
        done
      }

      cmd_profiles() {
        pritunl-client list --json 2>/dev/null | $JQ -r \
          '.[] | .name | gsub("[()]"; "") | gsub("maciej.flak "; "")'
      }

      case "''${1:-}" in
        connect|c) shift; cmd_connect "$@" ;;
        disconnect|d) shift; cmd_disconnect "$@" ;;
        status|s) cmd_status ;;
        profiles) cmd_profiles ;;
        *) echo "Usage: vpn {connect|c|disconnect|d|status|s} [profile]"; exit 1 ;;
      esac
    '')
  ];

  programs.zsh = {
    enable = true;
    interactiveShellInit = ''
      _vpn() {
        local -a subcmds profiles
        subcmds=('connect:Connect to VPN' 'c:Connect to VPN' 'disconnect:Disconnect VPN' 'd:Disconnect VPN' 'status:Show status' 's:Show status')
        if (( CURRENT == 2 )); then
          _describe 'command' subcmds
        elif (( CURRENT == 3 )); then
          case "$words[2]" in
            connect|c|disconnect|d)
              profiles=("''${(@f)$(vpn profiles 2>/dev/null)}")
              _describe 'profile' profiles
              ;;
          esac
        fi
      }
      compdef _vpn vpn
    '';
  };

  # Systemd service to auto-configure DNS when tun interface appears
  systemd.services.vpn-dns-config = {
    description = "Configure split DNS for VPN tunnel";
    wantedBy = [ ];  # Started by udev, not on boot
    after = [ "systemd-resolved.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
    };
    script = ''
      IFACE="$1"
      if [ -z "$IFACE" ]; then
        IFACE=$(${pkgs.iproute2}/bin/ip link show type tun 2>/dev/null | grep -oP 'tun\d+' | head -1)
      fi

      if [ -n "$IFACE" ]; then
        DNS_IP=$(${pkgs.iproute2}/bin/ip route show dev "$IFACE" | ${pkgs.gnugrep}/bin/grep -oP '(172\.20|101\.64|10\.96|10\.43)\.\d+\.\d+' | head -1 | ${pkgs.gnused}/bin/sed 's/\.[0-9]*$/\.10/')
        DNS_IP="''${DNS_IP:-172.20.0.10}"
        echo "Configuring DNS for $IFACE (DNS: $DNS_IP)"
        ${pkgs.systemd}/bin/resolvectl dns "$IFACE" "$DNS_IP"
        ${pkgs.systemd}/bin/resolvectl domain "$IFACE" "~cluster.local" "~svc.cluster.local"
        ${pkgs.systemd}/bin/resolvectl default-route "$IFACE" false
      fi
    '';
  };

  # udev rule to trigger DNS config when tun interface comes up
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="tun[0-9]*", TAG+="systemd", ENV{SYSTEMD_WANTS}+="vpn-dns-config.service"
  '';

  # Allow user to run pritunl-client without sudo
  security.sudo.extraRules = [
    {
      users = [ "flakm" ];
      commands = [
        { command = "${pkgs.pritunl-client}/bin/pritunl-client"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/pritunl-client"; options = [ "NOPASSWD" ]; }
        { command = "${pkgs.systemd}/bin/resolvectl"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/resolvectl"; options = [ "NOPASSWD" ]; }
      ];
    }
  ];
}
