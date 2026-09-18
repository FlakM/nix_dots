{ config, lib, pkgs, ... }:
let
  stats = pkgs.writeShellApplication {
    name = "quickshell-stats";
    runtimeInputs = [ pkgs.coreutils pkgs.gawk pkgs.iproute2 ];
    text = ''
      read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
      idle_a=$((idle + iowait))
      total_a=$((user + nice + system + idle + iowait + irq + softirq + steal))
      sleep 0.2
      read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
      idle_b=$((idle + iowait))
      total_b=$((user + nice + system + idle + iowait + irq + softirq + steal))
      cpu=$((100 * ((total_b - total_a) - (idle_b - idle_a)) / (total_b - total_a)))
      read -r mem_total mem_available < <(awk '
        /^MemTotal:/ { total=$2 }
        /^MemAvailable:/ { available=$2 }
        END { print total, available }
      ' /proc/meminfo)
      memory=$((100 * (mem_total - mem_available) / mem_total))
      disk=$(df -P / | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')
      load=$(awk -v cores="$(nproc)" '{ printf "%d", $1 * 100 / cores }' /proc/loadavg)
      io_pressure=$(awk -F'[ =]' '/^some/ { printf "%d", $3 }' /proc/pressure/io)
      memory_pressure=$(awk -F'[ =]' '/^some/ { printf "%d", $3 }' /proc/pressure/memory)
      temperature=0
      for hwmon in /sys/class/hwmon/hwmon*; do
        [ -r "$hwmon/name" ] || continue
        case "$(<"$hwmon/name")" in
          k10temp|coretemp|zenpower)
            for input in "$hwmon"/temp*_input; do
              [ -r "$input" ] || continue
              value=$(( $(<"$input") / 1000 ))
              [ "$value" -gt "$temperature" ] && temperature=$value
            done
            ;;
        esac
      done
      interface=$(ip -o route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
      if [ -z "$interface" ]; then
        interface=$(ip -o -6 route get 2606:4700:4700::1111 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
      fi

      network="offline"
      network_type="offline"
      address=""
      rx_rate=0
      tx_rate=0
      now=$(date +%s%3N)
      state="''${XDG_RUNTIME_DIR:-/tmp}/quickshell-network-state"

      if [ -n "$interface" ] && [ -r "/sys/class/net/$interface/statistics/rx_bytes" ]; then
        network="$interface"
        if [ -d "/sys/class/net/$interface/wireless" ]; then
          network_type="wifi"
        elif [[ "$interface" == tailscale* || "$interface" == tun* || "$interface" == wg* ]]; then
          network_type="vpn"
        else
          network_type="ethernet"
        fi
        address=$(ip -4 -o address show dev "$interface" scope global 2>/dev/null | awk 'NR == 1 { sub(/\/.*/, "", $4); print $4 }')
        rx=$(<"/sys/class/net/$interface/statistics/rx_bytes")
        tx=$(<"/sys/class/net/$interface/statistics/tx_bytes")

        if [ -r "$state" ]; then
          read -r previous_interface previous_rx previous_tx previous_time < "$state" || true
          if [ "$previous_interface" = "$interface" ] \
            && [[ "$previous_rx" =~ ^[0-9]+$ ]] && [[ "$previous_tx" =~ ^[0-9]+$ ]] \
            && [[ "$previous_time" =~ ^[0-9]+$ ]] && [ "$now" -gt "$previous_time" ] \
            && [ "$rx" -ge "$previous_rx" ] && [ "$tx" -ge "$previous_tx" ]; then
            elapsed=$((now - previous_time))
            rx_rate=$(((rx - previous_rx) * 1000 / elapsed))
            tx_rate=$(((tx - previous_tx) * 1000 / elapsed))
          fi
        fi
        printf '%s %s %s %s\n' "$interface" "$rx" "$tx" "$now" > "$state.tmp"
        mv "$state.tmp" "$state"
      else
        rm -f "$state" "$state.tmp"
      fi

      printf '{"cpu":%d,"memory":%d,"disk":%d,"temperature":%d,"load":%d,"ioPressure":%d,"memoryPressure":%d,"network":"%s","networkType":"%s","networkAddress":"%s","rxRate":%d,"txRate":%d}\n' \
        "$cpu" "$memory" "$disk" "$temperature" "$load" "$io_pressure" "$memory_pressure" \
        "$network" "$network_type" "$address" "$rx_rate" "$tx_rate"
    '';
  };
  clipboard = pkgs.writeShellApplication {
    name = "quickshell-clipboard";
    runtimeInputs = [ pkgs.cliphist pkgs.coreutils pkgs.jq pkgs.wl-clipboard ];
    text = ''
      case "''${1:-}" in
        list)
          cache="''${XDG_RUNTIME_DIR:-/tmp}/quickshell-clipboard"
          mkdir -p "$cache"
          cliphist list | head -n 30 | while IFS=$'\t' read -r id text; do
            mime=""
            type="text"
            preview=""
            if [[ "$text" =~ ^\[\[\ binary\ data.*\ (png|jpg|jpeg|webp|gif|bmp|tif|tiff)(\ |$) ]]; then
              format="''${BASH_REMATCH[1]}"
              mime="image/$format"
              [ "$format" = "jpg" ] && mime="image/jpeg"
              type="image"
              preview="$cache/$id"
              cliphist decode "$id" > "$preview"
              text="Image (''${format^^})"
            fi
            jq -cn \
              --arg id "$id" \
              --arg text "$text" \
              --arg type "$type" \
              --arg mime "$mime" \
              --arg preview "$preview" \
              '{ $id, $text, $type, $mime, $preview }'
          done | jq -s .
          ;;
        copy)
          if [[ "''${3:-}" == image/* ]]; then
            cliphist decode "''${2:?missing clipboard id}" | wl-copy --type "$3"
          else
            cliphist decode "''${2:?missing clipboard id}" | wl-copy
          fi
          ;;
        clear)
          cliphist wipe
          rm -rf "''${XDG_RUNTIME_DIR:-/tmp}/quickshell-clipboard"
          ;;
        *)
          printf 'usage: quickshell-clipboard list|copy ID|clear\n' >&2
          exit 2
          ;;
      esac
    '';
  };
  cameraActivity = pkgs.writeShellApplication {
    name = "quickshell-camera-activity";
    runtimeInputs = [ pkgs.mosquitto ];
    text = ''
      exec mosquitto_sub \
        --host 192.168.0.102 \
        --topic 'frigate/+/person' \
        --qos 1 \
        -R \
        --verbose
    '';
  };
  calendarAgenda = pkgs.writeShellApplication {
    name = "quickshell-calendar";
    runtimeInputs = [ pkgs.jq pkgs.khal ];
    text = ''
      khal list today 2d --day-format "" --format $'{start-date}\t{start-time}\t{end-time}\t{title}\t{calendar}' 2>/dev/null \
        | jq -Rn '[inputs | split("\t") | select(length >= 5) | {
            date: .[0], start: .[1], end: .[2], title: .[3], calendar: .[4]
          }]'
    '';
  };
  tailscaleStatus = pkgs.writeShellApplication {
    name = "quickshell-tailscale";
    runtimeInputs = [ pkgs.jq pkgs.tailscale pkgs.sudo ];
    text = ''
      case "''${1:-status}" in
        status)
          status=$(tailscale status --json 2>/dev/null || printf '{}')
          jq -cn --argjson status "$status" '{
            online: ($status.Self.Online // false),
            name: ($status.Self.HostName // "This device"),
            ip: ($status.Self.TailscaleIPs[0] // ""),
            peers: [($status.Peer // {} | to_entries[] | .value) | {
              name: (.HostName // (.DNSName // "Unknown") | rtrimstr(".")),
              ip: (.TailscaleIPs[0] // ""),
              os: (.OS // ""),
              online: (.Online // false),
              active: (.Active // false)
            }] | sort_by([(.online | not), .name])
          }'
          ;;
        up) exec sudo -n tailscale up ;;
        down) exec sudo -n tailscale down ;;
        *) printf 'usage: quickshell-tailscale status|up|down\n' >&2; exit 2 ;;
      esac
    '';
  };
in
{
  programs.quickshell = {
    enable = true;
    package = pkgs.quickshell;
    configs.desktop = ./quickshell/desktop;
    activeConfig = "desktop";
    systemd = {
      enable = true;
      target = "wayland-session@Hyprland.target";
    };
  };

  home.packages = [ stats clipboard cameraActivity calendarAgenda tailscaleStatus pkgs.material-symbols ];

  systemd.user.services.quickshell.Unit = {
    PartOf = [ "wayland-session@Hyprland.target" ];
    After = lib.mkForce [ "wayland-session@Hyprland.target" ];
    X-Restart-Triggers = [ "${./quickshell/desktop}" ];
  };
  systemd.user.services.quickshell.Service.Environment = [
    "QML2_IMPORT_PATH=${pkgs.qt6.qtmultimedia}/lib/qt-6/qml"
    "QT_PLUGIN_PATH=${pkgs.qt6.qtmultimedia}/lib/qt-6/plugins"
    "QT_FFMPEG_DECODING_HW_DEVICE_TYPES=,"
  ];

  systemd.user.services.cliphist = {
    Unit = {
      Description = "Clipboard history for QuickShell";
      PartOf = [ "wayland-session@Hyprland.target" ];
      After = [ "wayland-session@Hyprland.target" ];
    };
    Service = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "wayland-session@Hyprland.target" ];
  };

  systemd.user.services.cliphist-images = {
    Unit = {
      Description = "Image clipboard history for QuickShell";
      PartOf = [ "wayland-session@Hyprland.target" ];
      After = [ "wayland-session@Hyprland.target" ];
    };
    Service = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "wayland-session@Hyprland.target" ];
  };
}
