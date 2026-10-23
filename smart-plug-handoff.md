# Smart plug handoff — 2026-10-21 10:43 CEST

For new devices, follow [SMART_PLUG_PAIRING.md](SMART_PLUG_PAIRING.md), not the historical troubleshooting attempts below.

## Current result after follow-up — 2026-10-21

**Sypialnia dzieci is connected and controllable through Home Assistant. The older disconnected/RMA conclusions below are historical.**

- Current network: `dom_iot`, **192.168.0.145**, AP **jadalnia**, BSSID `26:e1:5d:01:73:e4`, **channel 1**, RSSI about −61 dBm.
- `switch.sypialnia_dzieci = off`, live power/energy readings available. An idempotent HA command was verified at the relay over BLE (`source: WS_in`) after the final reboot, without turning the load on.
- Outbound HA WebSocket is configured and **connected** to `ws://192.168.0.102:8123/api/shelly/ws`.
- **Reboot test passed**: BLE-triggered reboot, WiFi + HA WebSocket returned after ~71 seconds, still connected 15 seconds later. HA control re-verified afterward. Initial attempts on `piętro` remain problematic; this is recovery through another AP, not proof of the precise underlying firmware defect being fixed.
- Both kids' light automations are `on`; helper times **19:30 / 21:00**, pause `off`.
- The approved 20 MHz test on `piętro` was **reverted to the original width `"4"` (20/40 auto)** and verified via `getRadiosConfig`. The plug recovered through `jadalnia`, so width-only causation was not established. No permanent Omada configuration changes remain from this follow-up.
- Device firmware was **not changed**; setup AP is **disabled**, cloud remains disabled. Exact cause of the association-state mismatch with `piętro` is still unproven. If it recurs, capture association packets again; consider a separately approved stable firmware update or AP-lock test, rather than assuming a dead radio.

### Evidence and investigation history

- Reproduced the failure over BLE: `WiFi.GetStatus` disconnected/connecting, no IP; HA entities unavailable.
- Temporarily disabled `sta`, `sta1`, and the setup AP, then called raw `WiFi.Scan` over BLE. It detected both `dom` and `dom_iot` on channel 11 at **−58 dBm**. Another scan detected a neighboring network. The radio can scan; there is no basis yet for RMA.
- Important diagnostic bug: `diag_plug.sh` uses `[.results[]? ...]`, turning an RPC error object with no `results` into `[]`. Earlier empty output did **not** establish a successful scan finding zero networks. Preserve and inspect raw RPC errors.
- Captured device logs over the setup AP: `wifi:state: assoc -> init (0x400)`, `WiFi STA: Disconnected, reason: 4`, `Connect failed`. This is an association failure, before DHCP or HA pairing; the exact underlying cause is not established.
- Controller confirms WPA2/AES, PMF disabled, no SSID MAC filter, and client neither blocked nor locked to an AP. Compared provisioning-file PSK with controller PSK in memory: they match; no credential printed.
- Stopping/restarting STA and temporarily disabling AP did not immediately connect. The plug subsequently connected **before** a later credential refresh; therefore that refresh cannot be credited as the fix. No Omada settings changed or AP rebooted in this follow-up.
- At 10:58, verified HTTP RPC from both amd-pc and odroid, and Omada active client on `piętro`, SSID `dom_iot`, static IP **192.168.0.145**.
- HA switch is `off`; power and energy are `0.0`. Verified a HA switch command reached the plug (`Switch.GetStatus.source = WS_in`) while preserving its existing off state.
- HA schedule helpers are **19:30:00 / 21:00:00**, schedule pause is `off`.
- Outbound WebSocket was **not** automatically configured by HA (expected for non-battery devices). Explicitly set `Ws.SetConfig` to `enable:true`, `server:ws://192.168.0.102:8123/api/shelly/ws`; it required a plug reboot. **First reboot failed to reconnect within 100 seconds**. It later recovered on `piętro`; new HTTP connections subsequently timed out despite working WiFi and a working outbound HA connection. A separate BLE check confirmed HA commands still reached the relay. The final reboot/recovery via `jadalnia` is recorded above.
- Once online, `Shelly.CheckForUpdate` offers stable **2.1.0**, build `20261014-085737/2.1.0-g422283d`. Earlier “no firmware offered/current” observations were made while offline and are not reliable. **No firmware update performed.**
- Odroid's `PERMANENT` neighbor entry for `.145` remains unchanged.
- Monitor-mode packet capture `/tmp/opencode/shelly-association.pcapng` captured a concrete failed association: plug sends Open System authentication sequence 1; AP `26:e1:5d:01:75:b5` replies sequence 2, **status 0 (success)**; plug sends association request; AP sends **deauthentication reason 9** (requesting station not authenticated). This is not a WiFi password failure (the WPA handshake was never reached) or HA failure. Exact reason for AP/client authentication-state mismatch remains unknown.
- User approved a temporary **piętro 2.4 GHz width-only test, 40 MHz/auto → 20 MHz**. Applied `modifyRadiosConfig` with `radioSetting2g.channelWidth:"2"`. Original config saved to `/tmp/opencode/shelly-pietro-radio-before.json`; original width is `"4"`. **Original configuration has been restored.** 5 GHz settings and SSIDs unchanged.

Control UI: <https://homeassistant.house.flakm.com/smart-gniazdka/gniazdka>.

Follow-up diagnostic tools live in `/tmp/opencode/`: `shelly_diagnose.py` (read-only unless `--scan-idle`), `shelly_connection_trial.py`, `shelly_ap_probe.sh`, `shelly_wifi_events.py`, `shelly_ha_verify.py --ble` (sends an idempotent HA relay command; independently verifies it over BLE), `shelly_reconnect_check.py` (**reboots** via HTTP unless `--no-reboot`), and `shelly_ble_reboot_check.py` (**reboots** via BLE and checks WiFi + HA recovery). Temporary device debug logging was restored to its prior disabled state.

---

## TL;DR

- Goal: two Shelly Plug M Gen3 devices in Home Assistant:
  1. **Sypialnia dzieci** — kids' room light, on at **19:30**, off at **21:00**.
  2. **Biuro PC** — PC + monitor power/energy and cost tracking (not provisioned yet).
- The first plug is **not connected** to WiFi and HA reports `switch.sypialnia_dzieci` as **unavailable**.
- The `dom_iot` WLAN now exists and is correctly configured on the Omada controller; `piętro` was rebooted and its AP override includes `dom_iot`.
- The plug was provisioned several times (`dom`, `dom_iot`), factory-reset once, and provisioned again. It still reports `WiFi: disconnected` / `connecting` and its `WiFi.Scan` returns **no networks at all**, including `dom` which other clients use.
- That points to a **plug-side WiFi radio/firmware problem**, not an SSID configuration problem. The immediate next step is a **hard power cycle** (unplug 10 s). If it still cannot scan/join, the plug is likely faulty (RMA).
- Odroid HA networking was fixed and deployed: `internal_url` now points at the LAN and port 8123 is open. Commit `9cc726f`.
- Repo working tree is clean. This report is an untracked file.

---

## Current state at handoff

| Item | Value |
|---|---|
| Plug name | `Sypialnia dzieci` |
| Device ID | `shellyplugmg3-70af09fdc0fc` |
| WiFi MAC | `70:AF:09:FD:C0:FC` (`70-AF-09-FD-C0-FC`) |
| BLE MAC | `70:AF:09:FD:C0:FE` |
| Model | `S3PL-30110EU` (Shelly Plug M Gen3) |
| Firmware | `1.8.99-plugmg3prod0` (current; no newer firmware offered) |
| Static IP | `192.168.0.145` (DHCP reservation exists) |
| Current WiFi config | `dom_iot`, static, enabled |
| Current WiFi status | `disconnected` (sometimes `connecting`), `sta_ip=0.0.0.0`, `ssid=null`, `rssi=0` |
| Setup AP | **enabled** at handoff: `ShellyPlugMG3-70AF09FDC0FC` (open) |
| HA switch | `switch.sypialnia_dzieci` = `unavailable` |
| HA sensors | `sensor.sypialnia_dzieci_power`, `sensor.sypialnia_dzieci_energy` = `unavailable` |
| Omada active client | **not present** |
| Omada known client | `Sypialnia-dzieci`, MAC `70-AF-09-FD-C0-FC`, `ip:null`, `lastSeen` before the WiFi loss |
| HA Shelly config entry | loaded (`Sypialnia dzieci`), device unavailable |
| HA Matter entry | loaded, no Matter devices |

Latest `diag_plug.sh` output over the plug's setup AP:

```text
WIFI:        {"sta_ip":"0.0.0.0","status":"disconnected","ssid":null,"rssi":0}
WIFI_CFG:    {"sta":{"ssid":"dom_iot","enable":true,"ipv4mode":"static",
                     "ip":"192.168.0.145","pass_len":0},"ap":{"enable":true}}
SCAN_ALL:    []
WS_CFG:      {"enable":false,"server":null,"ssl_ca":"ca.pem"}
WS_STATUS:   {"connected":false}
CLOUD:       {"connected":false}
MQTT:        {"connected":false}
SYS:         {"uptime":..., "restart_required":false}
```

Notes:

- `pass_len:0` is **not proof** that the password is missing; the device/API may hide `sta.pass`.
- `WiFi.Scan` also returned `-114 Resource unavailable: Wifi scan failed!` over BLE.
- The plug cannot see `dom` either, even though other clients on `piętro` are using `dom`. This is the strongest evidence of a plug-side radio issue.
- The plug's BLE RPC is reachable and `auth_en:false`; BLE provisioning works at the API level, but the device does not associate.

---

## Hardware/network identifiers

| Item | Value |
|---|---|
| HA URL | `https://homeassistant.house.flakm.com` |
| HA LAN address | `192.168.0.102` (odroid) |
| HA LAN port | `8123` (now open) |
| AP `piętro` | `192.168.0.48`, MAC `20-E1-5D-01-75-B5`, model `EAP723(EU) v2.0` |
| AP `jadalnia` | MAC `20-E1-5D-01-73-E4` |
| Omada controller | `https://omada.house.flakm.com` |
| Omada site ID | `6a5625e443af3348ff66a466` |
| Omada Default WLAN group | `6a5625e543af3348ff66a47f` |
| `dom` SSID ID | `6a5625e843af3348ff66ad0f` |
| `dom_iot` SSID ID | `6ad86daa59356554879fda3c` |
| `dom_iot` AP-entry ID on `piętro` | `335487628` |
| Deleted old `dom_iot` ID | `6ad7b02a59356554879fceae` |
| HA Matter Server | `python-matter-server`, `127.0.0.1:5580` |

---

## Requirements / original constraints

- Kids' light schedule exactly **19:30 on / 21:00 off**.
- Office plug should measure **PC + monitor** consumption and compute cost.
- Add `dom_iot` as a **2.4 GHz** network via Omada.
- Matter Server should run on **odroid**, not amd-pc.
- Make the plug's IP persistent and visible in HA.
- Commit, deploy, verify HA connection.
- Prefer local control without the native Shelly app; app/BLE fallback acceptable.

---

## Repo changes and commits

Working tree at handoff: **clean**.

| Commit | Contents |
|---|---|
| `c4bdd91` | `hosts/odroid/smart-plugs.nix`: Shelly entities, kids' schedule 19:30/21:00, utility meters, cost sensors, dashboard, automations |
| `1bb973b` | `hosts/odroid/matter-server.nix`, Matter integration, Shelly AP provisioning helper; deployed to odroid |
| `9cc726f` | `hosts/odroid/home-assistant.nix`: LAN `internal_url` + open port 8123; deployed to odroid |

### `hosts/odroid/smart-plugs.nix`

- Kids' entities: `switch.sypialnia_dzieci`, `sensor.sypialnia_dzieci_power`, `sensor.sypialnia_dzieci_energy`.
- Office entities: `switch.biuro_pc`, `sensor.biuro_pc_power`, `sensor.biuro_pc_energy`, plus utility meters and cost sensors:
  - `sensor.biuro_pc_energia_dzis`
  - `sensor.biuro_pc_energia_miesiac`
  - `sensor.biuro_pc_koszt_godzina`
  - `sensor.biuro_pc_koszt_dzis`
  - `sensor.biuro_pc_koszt_miesiac`
  - `sensor.biuro_pc_praca_dzis`
  - `binary_sensor.biuro_pc_pracuje`
- Inputs: `input_boolean.sypialnia_dzieci_harmonogram_wstrzymany`, `input_datetime.sypialnia_dzieci_wlacz`, `input_datetime.sypialnia_dzieci_wylacz`.
- Automations: kids' light on at 19:30, off at 21:00.
- Dashboard: `smart-gniazdka` (hyphen is required by the Lovelace URL).
- HA `extraComponents`: `shelly`, `utility_meter`, `matter`.

### `hosts/odroid/matter-server.nix` / `home-assistant.nix`

- Matter Server runs as an odroid systemd service on `127.0.0.1:5580`.
- HA Matter integration is loaded; no Matter devices are paired.
- Odroid has no usable Bluetooth for commissioning; the HA Companion app uses the phone's BLE.

### `hosts/odroid/home-assistant.nix` (the odroid networking fix)

Before the fix:

- `internal_url` was the **public** URL `https://homeassistant.house.flakm.com`.
- HA listened on `0.0.0.0:8123`, but **8123 was firewalled from the LAN** (curl timed out); 443 worked.
- The Shelly plug's `Ws.GetConfig` was `{enable:false, server:null}`, so HA used inbound RPC. The Gen3 ARP bug made the device unavailable.
- Route to `.145` was via `enp2s0`; a static `PERMANENT` ARP entry for `.145` existed. `rp_filter` was `all=0`, `enp2s0=2` (loose).

After the fix:

```nix
services.home-assistant.openFirewall = true;
...
internal_url = "http://192.168.0.102:8123";
```

Deployed. Verified:

- `http://192.168.0.102:8123` returns **200** from the LAN.
- `https://homeassistant.house.flakm.com` still returns 200.
- HA `internal_url` is `http://192.168.0.102:8123`.

This lets the Shelly integration configure the plug's outbound WebSocket to `ws://192.168.0.102:8123/api/shelly/ws` once the plug joins WiFi. The plug's `Ws` is still disabled because it never joined.

---

## Omada WLAN work

### `dom`

- Security: WPA3-SAE (`security:3`, `pskSetting.versionPsk:4`, `pmfMode:2`).
- Band: `7` in the API; AP override `getWlansConfigV2` shows `band:[0,1]` (2.4 + 5; AP has no 6 GHz).
- `multiCast`: `arpCastEnable:true`, `ipv6CastEnable:true`, `multiCastEnable:true` (Omada defaults).
- The plug originally connected to `dom` at `.145`, then became ARP-unresponsive. The `piętro` AP was rebooted to clear ARP state; the plug did not rejoin.
- Do not churn `dom`; it is the main WPA3 network and other clients use it.

### `dom_iot` (created via Omada API)

The previous API-created `dom_iot` (`6ad7b02a59356554879fceae`) had hidden isolation defaults and was deleted. The new SSID is:

- Name: `dom_iot`
- SSID ID: `6ad86daa59356554879fda3c`
- Band: `1` = **2.4 GHz only**
- Security: `3` = WPA-Personal
- `pskSetting.versionPsk`: `2` = **WPA2-PSK**
- `pskSetting.encryptionPsk`: `3` = AES
- `pskSetting.gikRekeyPskEnable`: false
- `pmfMode`: `3` = **Disable**
- `broadcast`: true
- `guestNetEnable`: false
- `prohibitWifiShare`: false
- `vlanEnable`: false; `vlanSetting.mode`: 0
- `mloEnable`: false
- `enable11r`: false
- `deviceType`: 3
- `hidePwd`: false
- The PSK is **not** in this report. It is in `/tmp/opencode/dom_iot.psk` (24 bytes) and in the create/update JSON files listed below.

Create body (PSK placeholder):

```json
{
  "band": 1,
  "broadcast": true,
  "deviceType": 3,
  "enable11r": false,
  "guestNetEnable": false,
  "hidePwd": false,
  "mloEnable": false,
  "name": "dom_iot",
  "pmfMode": 3,
  "security": 3,
  "vlanEnable": false,
  "prohibitWifiShare": false,
  "pskSetting": {
    "encryptionPsk": 3,
    "gikRekeyPskEnable": false,
    "versionPsk": 2,
    "securityKey": "<read /tmp/opencode/dom_iot.psk>"
  },
  "vlanSetting": { "mode": 0 }
}
```

After creation, multicast/ARP isolation was explicitly disabled:

```json
{
  "arpCastEnable": false,
  "channelUtil": 100,
  "filterEnable": false,
  "ipv6CastEnable": false,
  "multiCastEnable": false
}
```

Verified via `getSsidDetail`: `multiCast` all false, `pmfMode:3`, `band:1`, `security:3`, `pskSetting.versionPsk:2`.

### AP verification and reboot

- `getWlansConfigV2` for **`piętro`** shows `dom_iot` with `ssidEnable:true`, `band:[0]`, `ssidEntryId:335487628`, `ssidId:6ad86...`, `vlanId:1`.
- `piętro` was rebooted via `omada rebootDevice --site-id ... --device-mac 20-E1-5D-01-75-B5`; the API returned status 13, and the AP's uptime reset (it did reboot).
- **`jadalnia` was not rebooted.** Its runtime broadcast of `dom_iot` is unverified. The controller config should apply it, but a reboot may be needed.
- Band mapping was confirmed with a temporary `dom_iot_probe` SSID:
  - `band:2` → `getWlansConfig` `band:[1]` (5 GHz)
  - `band:1` → `band:[0]` (2.4 GHz)
  - Therefore `dom_iot` is genuinely 2.4 GHz.
- The `dom_iot_probe` was deleted; no temporary SSID remains.
- An attempt to change `dom_iot` to `band:7` via `updateSsidBasicConfig` returned `-1001 Invalid request parameters` and did **not** change the SSID. It remains `band:1`.

### Important Omada OpenAPI observations

- `createSsid` with `band:1` creates a 2.4-only SSID; `getWlansConfig` reports `band:[0]`.
- `createSsid` with `band:2` creates a 5-only SSID; `getWlansConfig` reports `band:[1]`.
- `createSsid` defaults `multiCast` to true for ARP/IPv6/multicast; this must be explicitly patched off for IoT SSIDs.
- An API-created SSID can silently get isolation defaults; always verify `multiCast`, `guestNetEnable`, `prohibitWifiShare`, and VLAN after creation.
- `updateSsidBasicConfig` rejected a band change from 1 to 7 with `-1001`; if a band change is needed, delete/recreate the SSID.

---

## Plug provisioning attempts (chronological)

1. Plug initially provisioned to `dom` via `scripts/shelly-provision.sh`; it connected at `.145`; switch test worked (voltage 243.6 V, power 0 W with no load), then became ARP-unresponsive.
2. `piętro` was rebooted to clear ARP; the plug did not rejoin `dom`; its setup AP became active.
3. Plug firmware checked: `1.8.99-plugmg3prod0`; `Shelly.Update` returned `-114 Resource unavailable: No update info!`; no newer firmware.
4. First API-created `dom_iot` (`6ad7b...`) had hidden isolation; deleted. New `dom_iot` (`6ad86...`) created and verified as above.
5. Provisioned to `dom_iot` via the setup AP: API success, but `WiFi.GetStatus` remained `disconnected`/`connecting`; no Omada active client; `.145` unreachable.
6. BLE diagnostics: `WiFi.Scan` `-114`; `WiFi.GetStatus` `connecting`; `Ws` disabled.
7. **Factory reset** via BLE (`Shelly.FactoryReset`) succeeded; setup AP came back.
8. Provisioned to `dom_iot` again via the setup AP: API success; still no association.
9. Provisioned to `dom` again: API success; still no association.
10. Latest: provisioned to `dom_iot` again; still no association. The setup AP was then re-enabled via BLE and is currently visible.

No step produced an Omada active client, a `.145` response, or an HA `switch` state.

### What the plug reports

- `WiFi.GetStatus`: `disconnected` / `connecting`, `sta_ip=0.0.0.0`, `ssid=null`, `rssi=0`.
- `WiFi.GetConfig`: `sta.ssid=dom_iot`, `sta.enable=true`, `ipv4mode=static`, `ip=192.168.0.145`, `ap.enable=true` (at handoff).
- `WiFi.Scan`: empty / `-114`; it does not see `dom` either.
- `Ws.GetConfig`: `enable:false`, `server:null`; `Ws.GetStatus.connected:false`.
- `Cloud`: false; `MQTT`: false.
- `Shelly.GetDeviceInfo`: `auth_en:false`, `provision:null`, firmware current.
- BLE RPC works; BLE MAC `70:AF:09:FD:C0:FE`.

### Current interpretation

The `dom_iot` config is almost certainly fine. The plug's own WiFi scan sees **nothing**, while `dom` is definitely broadcast and used by other clients on `piętro`. That is a plug-side WiFi radio/firmware failure or a stuck radio state. A factory reset via software did not fix it; a **physical power cycle** is the next meaningful step.

Alternative possibility: `dom_iot` is not actually broadcast on `piętro` despite the controller config. This should be checked from a phone near `piętro` (does `dom_iot` appear in the WiFi list?). If it does not appear, reboot `jadalnia` and re-check both APs; then re-check the AP runtime config. If it does appear, the plug radio is the problem.

---

## HA state

- `switch.sypialnia_dzieci` = `unavailable`.
- `sensor.sypialnia_dzieci_power` = `unavailable`.
- `sensor.sypialnia_dzieci_energy` = `unavailable`.
- The Shelly integration config entry for `Sypialnia dzieci` is loaded, but the device is unavailable.
- The kids' schedule automations cannot run until the switch is available.
- The office plug (`Biuro PC`) has not been provisioned; its entities will remain missing/unavailable until it is set up.

### HA / odroid deployment

```sh
nixos-rebuild switch --target-host flakm@192.168.0.102 --sudo \
  --flake ~/programming/flakm/nix_dots#odroid
```

Verified after deploy:

- `home-assistant.service` active.
- `matter-server` active/listening on `127.0.0.1:5580`.
- `http://192.168.0.102:8123` returns 200 from the LAN.
- HA `internal_url` is `http://192.168.0.102:8123`; `external_url` remains `https://homeassistant.house.flakm.com`.

---

## Useful commands for the next agent

### Omada environment

From the repo root, with sops access:

```sh
export OMADA_BASE_URL=https://omada.house.flakm.com
export OMADA_SSL_VERIFY=true
export OMADA_CLIENT_ID="$(nix shell nixpkgs#sops -c sops decrypt secrets/secrets.yaml | yq -r .omada_client_id)"
export OMADA_CLIENT_SECRET="$(nix shell nixpkgs#sops -c sops decrypt secrets/secrets.yaml | yq -r .omada_client_secret)"
omada auth
```

If `sops`/`yq`/`curl` disappear from `PATH` after a `nix shell` command substitution, use absolute paths or a single `nix shell -c` wrapper. The environment has had that quirk.

Useful reads:

```sh
omada getSsidList --site-id 6a5625e443af3348ff66a466 \
  --wlan-id 6a5625e543af3348ff66a47f --page 1 --page-size 100

omada getSsidDetail --site-id 6a5625e443af3348ff66a466 \
  --wlan-id 6a5625e543af3348ff66a47f --ssid-id 6ad86daa59356554879fda3c

omada getWlansConfigV2 --site-id 6a5625e443af3348ff66a466 \
  --ap-mac 20-E1-5D-01-75-B5

omada getGridActiveClients --site-id 6a5625e443af3348ff66a466 \
  --page 1 --page-size 1000

omada getGridKnownClients --site-id 6a5625e443af3348ff66a466 \
  --page 1 --page-size 1000

omada getDeviceList --site-id 6a5625e443af3348ff66a466 \
  --page 1 --page-size 100

omada rebootDevice --site-id 6a5625e443af3348ff66a466 \
  --device-mac 20-E1-5D-01-75-B5
```

### Provision the plug over its setup AP

The agent shell lacks `CAP_NET_ADMIN`; use a transient root unit:

```sh
systemd-run --user --wait --pipe --unit=shelly-provision-$(date +%s) \
  /run/wrappers/bin/sudo -n bash \
  /home/flakm/programming/flakm/nix_dots/scripts/shelly-provision.sh \
  --name "Sypialnia dzieci" --ssid dom_iot \
  --psk-file /tmp/opencode/dom_iot.psk
```

Find the setup AP:

```sh
systemd-run --user --wait --pipe --unit=shelly-scan-$(date +%s) \
  /run/wrappers/bin/sudo -n bash \
  /home/flakm/.cache/shelly-provision/find_ap.sh
```

Diagnose over the setup AP:

```sh
systemd-run --user --wait --pipe --unit=shelly-diag-$(date +%s) \
  /run/wrappers/bin/sudo -n bash \
  /home/flakm/.cache/shelly-provision/diag_plug.sh
```

Note: `wlp13s0` scans can be flaky/empty after provisioning; `iw dev wlp13s0 scan` sometimes returns nothing even for known APs. Do not over-interpret a single empty scan from the amd-pc. The plug's own `WiFi.Scan` being empty for `dom` is more significant, but note that `WiFi.Scan` over the setup AP may also be restricted in AP mode.

### BLE helpers

The plug's BLE RPC works. Use `aioshelly`'s BLE provisioning:

```sh
nix shell --impure --expr \
  'let pkgs = import (builtins.getFlake "nixpkgs") {}; in pkgs.python3.withPackages (ps: [ ps.aioshelly ])' \
  -c python3 /tmp/opencode/ble_probe.py
```

BLE MAC: `70:AF:09:FD:C0:FE`.

Relevant helpers in `/tmp/opencode/`:

- `ble_probe.py` — read-only: device info, WiFi status/config.
- `ble_enable_ap.py` — enables the setup AP (`WiFi.SetConfig ap.enable=true`).
- `ble_reboot_ap.py` — enables AP then reboots.
- `ble_factory_reset.py` — **destructive**: `Shelly.FactoryReset`.
- `ble_provision_dom_iot.py` — sets `Sys.SetConfig`, `Cloud.SetConfig`, `WiFi.SetConfig` for `dom_iot` (reads `/tmp/opencode/dom_iot.psk`).
- `ble_wifi_scan.py` / `ble_wifi_scan2.py` — WiFi scan attempts (currently fail/empty).
- `ble_reboot_check.py` — reads config, then `Shelly.Reboot`.

`aioshelly` pattern used:

```python
from bleak import BleakScanner
from aioshelly.ble.provisioning import ble_rpc_device

dev = await BleakScanner.find_device_by_address("70:AF:09:FD:C0:FE", timeout=25)
async with ble_rpc_device(dev) as device:
    await device.call_rpc("WiFi.GetStatus")
    await device.call_rpc("WiFi.SetConfig", {"config": {"sta": {...}}})
```

The device hides `sta.pass` in `WiFi.GetConfig` (`pass_len:0`); this is not proof the password is missing.

### HA state check

```sh
timeout 90 nix-shell -p python3Packages.aiohttp \
  --run 'python3 /tmp/opencode/state.py'
```

`/tmp/opencode/state.py` performs the HA token exchange and prints the entity states. It reads HA auth data on the odroid; do not share tokens.

### Omada UI/session

The OpenAPI client is sufficient for everything done so far. A UI session can be obtained with the sops keys `omada_ha_username` / `omada_ha_password` against `POST /{omadacId}/api/v2/login` and cookies, but the UI API paths differ from OpenAPI; this was not needed for the WLAN creation.

---

## Files and artifacts

### Repo

- `hosts/odroid/smart-plugs.nix` — kids' schedule, office meters/cost, dashboard, automations.
- `hosts/odroid/matter-server.nix` — odroid Matter Server service.
- `hosts/odroid/configuration.nix` — imports `matter-server.nix`.
- `hosts/odroid/home-assistant.nix` — HA components, `internal_url`, `openFirewall`.
- `scripts/shelly-provision.sh` — setup-AP provisioning; sets name, WiFi, static IP, cloud off, AP off.
- `secrets/secrets.yaml` — sops-encrypted Omada/HA credentials.
- `home-manager/modules/omada-skill/SKILL.md` — Omada CLI workflow.

### Cache / temp

- `/home/flakm/.cache/shelly-provision/find_ap.sh` — scan for setup AP.
- `/home/flakm/.cache/shelly-provision/diag_plug.sh` — read-only AP diagnostic; edited to print `WIFI_CFG`, `SCAN_ALL`.
- `/home/flakm/.cache/shelly-provision/reboot_plug.sh` — ECO off + reboot + AP disable.
- `/home/flakm/.cache/shelly-provision/update_firmware.sh` — OTA attempt / ECO disable.
- `/home/flakm/.cache/shelly-provision/bin/` — `wpa_supplicant`, `iw`, `curl` symlinks.
- `/home/flakm/.cache/shelly-provision/dom.psk` — `dom` PSK (14 bytes incl. newline).
- `/tmp/opencode/dom_iot.psk` — `dom_iot` PSK (24 bytes).
- `/tmp/opencode/dom_iot_create.json`, `/tmp/opencode/dom_iot_basic.json` — Omada API bodies; **contain the `dom_iot` PSK**. Mode 600. Do not commit or paste.
- `/tmp/opencode/state.py` — HA token/entity check.
- `/tmp/opencode/add_shelly_v2.py` — earlier HA Shelly config-flow helper (not needed now).
- `/tmp/opencode/ble_*.py` — BLE helpers listed above.

### On odroid

- `/var/lib/hass/.storage/auth` — HA refresh tokens; readable via `sudo -n`; do not share.
- `/etc/home-assistant/configuration.yaml` — rendered HA config; `internal_url` is `http://192.168.0.102:8123`.
- `matter-server` service; `127.0.0.1:5580`.

---

## Security / cleanup

- Do **not** paste the `dom`/`dom_iot` PSKs or Omada/HA credentials into chat, commits, or this report.
- The following files contain secrets and are mode 600:
  - `/home/flakm/.cache/shelly-provision/dom.psk`
  - `/tmp/opencode/dom_iot.psk`
  - `/tmp/opencode/dom_iot_create.json`
  - `/tmp/opencode/dom_iot_basic.json`
- `secrets/secrets.yaml` is sops-encrypted; do not decrypt into the repo.
- This report contains internal MACs/IPs/IDs but no passwords; it is untracked (`smart-plug-handoff.md`).

---

## Recommended next steps (in order)

1. **Hard power cycle the plug**: unplug for ~10 s, plug back in. Watch the LED:
   - Blue/setup AP → run `find_ap.sh`, then `shelly-provision.sh --ssid dom_iot`; wait 30–60 s; verify.
   - No setup AP → hold the button ~5 s within 60 s of power-up to force AP mode, or use BLE `ble_enable_ap.py`.
2. **Check whether `dom_iot` is visible on a phone near `piętro`.** If yes, the AP is broadcasting and the plug is at fault. If no, reboot `jadalnia` too and re-check; then inspect both APs' `getWlansConfigV2`.
3. If the plug joins:
   - Verify Omada active client (`70-AF-09-FD-C0-FC`, SSID `dom_iot`, IP `.145`).
   - `ping 192.168.0.145`; `curl http://192.168.0.145/shelly`.
   - Check HA `switch.sypialnia_dzieci` / sensors.
   - Check `Ws.GetConfig` on the plug; the HA integration should configure `ws://192.168.0.102:8123/api/shelly/ws` now that 8123 is open and `internal_url` is LAN.
   - Check HA logs for `shelly`/`ws`.
   - Confirm the 19:30/21:00 automations and the `sensor.sypialnia_dzieci_*` entities.
4. If the plug still cannot see any SSID after a hard power cycle, treat it as **faulty (RMA)**. It has already been factory-reset and re-provisioned several times; further resets are unlikely to help.
5. Optional odroid cleanup:
   - Check `ip neigh show 192.168.0.145`; a `PERMANENT` static ARP entry may remain from earlier debugging. Remove it if it causes confusion.
   - `rp_filter` on `enp2s0` is `2` (loose); not currently believed to be the cause.
6. Once the first plug is stable, provision the second plug as **`Biuro PC`**:
   - Use the same `dom_iot` WLAN and `shelly-provision.sh` with `--name "Biuro PC"`.
   - Choose a new static IP (e.g. `.146`) and add a DHCP reservation; `STATIC_IP=...` is an env override in the script.
   - Verify `switch.biuro_pc`, `sensor.biuro_pc_power`, `sensor.biuro_pc_energy`, the utility meters, and cost sensors.
   - The cost/schedule logic already exists in `hosts/odroid/smart-plugs.nix`.
7. Optional: if Matter is not needed for these plugs, remove the Matter integration retry noise; it currently has no devices.

---

## Open questions for the next agent / user

- What is the plug's LED doing after a hard power cycle? (Blue setup AP, flashing, off?)
- Does `dom_iot` appear in a phone's WiFi list near `piętro`?
- Was `jadalnia` rebooted after `dom_iot` was created? (Currently: no.)
- Is the plug physically reachable for an unplug/replug and a 5 s button press?
- Is the plug's 2.4 GHz radio actually working? Its scan returns no networks even for `dom`; this is the key unresolved symptom.
