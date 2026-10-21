#!/usr/bin/env bash
# Provision a Shelly Gen2/Gen3 device over its setup AP, without the Shelly app.
#
# Connects a spare WiFi interface to the device's setup AP (192.168.33.1),
# sets the Shelly device name, joins it to the home WiFi, disables the setup AP
# and the cloud, then verifies the device from the wired LAN.
#
# Must run as root: it creates a wpa_supplicant session and configures an IP.
#
# Example:
#   sudo bash scripts/shelly-provision.sh --name "Sypialnia dzieci" --ssid dom
#
# The WiFi password is read from ~/.cache/shelly-provision/wifi.psk when it
# exists; otherwise it is prompted for. Pass --psk-file to override.
set -euo pipefail

export PATH="/run/current-system/sw/bin:/run/current-system/sw/sbin:$PATH"

RUN_USER="${SUDO_USER:-$(id -un)}"
RUN_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"
export PATH

IFACE="${IFACE:-wlp13s0}"
NAME=""
SSID=""
PSK_FILE=""
AP_SSID=""
AP_PSK=""
TOOLS="${TOOLS:-$RUN_HOME/.cache/shelly-provision/bin}"
DEFAULT_PSK_FILE="$RUN_HOME/.cache/shelly-provision/wifi.psk"
STATIC_IP="${STATIC_IP:-192.168.0.145}"
STATIC_MASK="${STATIC_MASK:-255.255.255.0}"
STATIC_GW="${STATIC_GW:-192.168.0.1}"
STATIC_DNS="${STATIC_DNS:-192.168.0.1}"

WPA_CONF="/run/shelly-wpa.conf"
WPA_PID="/run/shelly-wpa.pid"
WPA_LOG="/run/shelly-wpa.log"
BASE=""

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "==> $*"; }

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface) IFACE="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --ssid) SSID="$2"; shift 2 ;;
    --psk-file) PSK_FILE="$2"; shift 2 ;;
    --ap-ssid) AP_SSID="$2"; shift 2 ;;
    --ap-psk) AP_PSK="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ ${EUID} -eq 0 ]] || die "run as root (sudo)"
if [[ -z "$PSK_FILE" && -s "$DEFAULT_PSK_FILE" ]]; then
  PSK_FILE="$DEFAULT_PSK_FILE"
fi
[[ -n "$NAME" ]] || die "--name is required"
[[ -n "$SSID" ]] || die "--ssid is required"
[[ -z "$PSK_FILE" || -s "$PSK_FILE" ]] || die "--psk-file must be non-empty"

WPA="$TOOLS/wpa_supplicant"
IW="$TOOLS/iw"
CURL="$TOOLS/curl"
for t in "$WPA" "$IW" "$CURL"; do
  [[ -x "$t" ]] || die "missing tool: $t (set TOOLS=...)"
done

CLEANED=0
cleanup() {
  [[ "$CLEANED" -eq 1 ]] && return 0
  CLEANED=1
  set +e
  if [[ -f "$WPA_PID" ]]; then
    kill "$(cat "$WPA_PID")" 2>/dev/null
  fi
  pkill -f "wpa_supplicant.*-i $IFACE" 2>/dev/null
  ip addr flush dev "$IFACE" 2>/dev/null
  ip link set "$IFACE" down 2>/dev/null
  rm -f "$WPA_CONF" "$WPA_PID"
}
trap cleanup EXIT

log "bringing up $IFACE"
rfkill unblock wifi 2>/dev/null || true
ip link set "$IFACE" up

log "scanning for the Shelly setup AP"
SCAN="$("$IW" dev "$IFACE" scan 2>/dev/null | tr -d '\r' || true)"
[[ -n "$SCAN" ]] || die "WiFi scan returned nothing (is $IFACE usable?)"

if [[ -z "$AP_SSID" ]]; then
  mapfile -t SHELLY_SSIDS < <(printf '%s\n' "$SCAN" | awk -F': ' '/SSID:/ {print $2}' | grep -i 'shelly' | sort -u || true)
  if [[ ${#SHELLY_SSIDS[@]} -eq 1 ]]; then
    AP_SSID="${SHELLY_SSIDS[0]}"
  elif [[ ${#SHELLY_SSIDS[@]} -gt 1 ]]; then
    printf 'Multiple Shelly setup APs found:\n' >&2
    printf '  %s\n' "${SHELLY_SSIDS[@]}" >&2
    die "pass --ap-ssid to choose one"
  fi
fi
[[ -n "$AP_SSID" ]] || die "no Shelly setup AP found; pass --ap-ssid"
log "using setup AP: $AP_SSID"

if [[ -n "$PSK_FILE" ]]; then
  PSK="$(cat "$PSK_FILE")"
elif [[ -n "${SHELLY_WIFI_PSK:-}" ]]; then
  PSK="$SHELLY_WIFI_PSK"
else
  read -rsp "WiFi password for '$SSID': " PSK
  echo
fi
[[ -n "$PSK" ]] || die "empty WiFi password"

if [[ -n "$AP_PSK" ]]; then
  cat > "$WPA_CONF" <<EOF
network={
  ssid="$AP_SSID"
  psk="$AP_PSK"
}
EOF
else
  cat > "$WPA_CONF" <<EOF
network={
  ssid="$AP_SSID"
  key_mgmt=NONE
}
EOF
fi

log "associating with $AP_SSID"
rm -f "$WPA_LOG"
"$WPA" -B -D nl80211 -i "$IFACE" -c "$WPA_CONF" -P "$WPA_PID" -f "$WPA_LOG"

for _ in $(seq 1 25); do
  grep -q "CTRL-EVENT-CONNECTED" "$WPA_LOG" 2>/dev/null && break
  sleep 1
done
grep -q "CTRL-EVENT-CONNECTED" "$WPA_LOG" 2>/dev/null || { cat "$WPA_LOG" >&2; die "did not associate"; }

ip addr flush dev "$IFACE"
ip addr add 192.168.33.2/24 dev "$IFACE"

log "waiting for the device web server at 192.168.33.1"
for _ in $(seq 1 20); do
  if "$CURL" -sSLk --noproxy '*' --max-time 5 "https://192.168.33.1/shelly" >/dev/null 2>&1; then
    BASE="https://192.168.33.1"
    break
  fi
  if "$CURL" -sSLk --noproxy '*' --max-time 5 "http://192.168.33.1/shelly" >/dev/null 2>&1; then
    BASE="http://192.168.33.1"
    break
  fi
  sleep 1
done
[[ -n "$BASE" ]] || { cat "$WPA_LOG" >&2; die "cannot reach 192.168.33.1"; }
log "web server: $BASE"

get() { "$CURL" -sSLk --noproxy '*' --max-time 10 "$BASE/rpc/$1"; }
setconf() {
  local method="$1" cfg="$2" body f
  body="$(jq -cn --arg m "$method" --argjson c "$cfg" '{id:1,method:$m,params:{config:$c}}')"
  f="$(mktemp /run/shelly-body.XXXXXX)"
  printf '%s' "$body" > "$f"
  "$CURL" -sSLk --noproxy '*' --max-time 10 -X POST "$BASE/rpc" -H 'Content-Type: application/json' --data-binary @"$f"
  local rc=$?
  rm -f "$f"
  return $rc
}

INFO="$(get Shelly.GetDeviceInfo)"
echo "$INFO" | jq -r '"device: \(.id)  mac: \(.mac)  model: \(.model // "n/a")  fw: \(.ver)  provision: \(.provision // "n/a")  auth: \(.auth_en)"'
[[ "$(echo "$INFO" | jq -r '.auth_en // false')" == "true" ]] && die "device auth is enabled; cannot continue"

log "setting device name to '$NAME'"
setconf Sys.SetConfig "$(jq -cn --arg n "$NAME" '{device:{name:$n}}')" >/dev/null
setconf Sys.SetConfig '{"location":{"tz":"Europe/Warsaw"}}' >/dev/null 2>&1 || true

log "configuring WiFi '$SSID'"
setconf WiFi.SetConfig "$(jq -cn --arg s "$SSID" --arg p "$PSK" --arg ip "$STATIC_IP" --arg mask "$STATIC_MASK" --arg gw "$STATIC_GW" --arg dns "$STATIC_DNS" '{sta:{ssid:$s,pass:$p,enable:true,ipv4mode:"static",ip:$ip,netmask:$mask,gw:$gw,nameserver:$dns}}')" >/dev/null

log "disabling the setup AP to force STA mode"
setconf Cloud.SetConfig '{"enable":false}' >/dev/null 2>&1 || true
setconf WiFi.SetConfig '{"ap":{"enable":false}}' >/dev/null 2>&1 || true
sleep 4
cleanup
trap - EXIT
log "WiFi '$SSID' configured; setup AP disabled."
log "MAC: $(echo "$INFO" | jq -r '.mac')"
