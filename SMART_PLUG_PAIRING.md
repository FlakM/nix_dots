# Pairing Shelly smart plugs with Home Assistant

Procedure for **Shelly Plug M Gen3**, verified on 2026-10-21. Use the local
**Shelly integration**, not Matter commissioning. No Shelly account, cloud
connection, phone app, or new NixOS deployment is needed for the second plug.

## Device plan

| Device name | LAN IP | HA switch | Status |
|---|---|---|---|
| `Sypialnia dzieci` | `192.168.0.145` | `switch.sypialnia_dzieci` | Already paired; leave unchanged |
| `Biuro PC` | `192.168.0.146` | `switch.biuro_pc` | Paired 2026-10-21 (MAC `70:AF:09:FE:35:BC`); see record at the end |

The office plug's dashboard, power/energy meters, and cost calculations already
exist in [`hosts/odroid/smart-plugs.nix`](hosts/odroid/smart-plugs.nix).
Later devices need their own unused IP, name, and any desired dashboard entries.

## 1. Prepare and identify the new plug

1. **Leave the PC and monitor disconnected during setup and reboot tests.** Use
   an empty plug or a harmless test lamp. Never toggle a running PC to test pairing.
2. Initially power the new plug near **jadalnia**. The first plug had intermittent
   association failures with **piętro**, but recovered through jadalnia. This is a
   practical starting point, not a guarantee for every device.
3. Identify its setup SSID, usually `ShellyPlugMG3-<MAC>`, from a phone's Wi-Fi
   list or a workstation scan. Record the **Wi-Fi MAC**, not the BLE MAC. Do not
   assume the second plug has the first plug's MAC or Bluetooth address.
4. Check Omada's DHCP reservations and active/known clients for an address conflict;
   reserve `.146` for **this new Wi-Fi MAC**. A failed ping alone does not prove an
   address is free. Use the Omada UI or discover the reservation operation with
   `omada list` and inspect `omada schema <operation>` before changing it.

Use the existing WLAN:

- SSID: **`dom_iot`**, 2.4 GHz, WPA2-PSK/AES, PMF disabled.
- Same LAN as HA; no guest/client isolation or separate VLAN required here.
- Do not recreate the SSID, rotate its password, or change the main `dom` WLAN.

Home Assistant is on **odroid**, `192.168.0.102:8123`, with LAN access already
enabled. Its web UI is <https://homeassistant.house.flakm.com>.

## 2. Keep the existing Wi-Fi password private

The provisioning helper needs a file containing the **current `dom_iot` PSK**.
Preferred local path: `~/.cache/shelly-provision/dom_iot.psk`, permissions `600`.
Do not put the password in this repository, command arguments, logs, or chat.

For this session, the password already exists in `/tmp/opencode/dom_iot.psk`.
If that file still exists, save a private reusable copy:

```bash
install -d -m 700 "$HOME/.cache/shelly-provision"
install -m 600 /tmp/opencode/dom_iot.psk \
  "$HOME/.cache/shelly-provision/dom_iot.psk"
```

If the temporary file is gone, obtain the existing PSK from Omada and save it
privately at the preferred path. **Do not generate a new PSK for each plug.**

## 3. Provision over the new plug's setup AP

Run from **amd-pc on wired Ethernet**. The helper takes over the spare
`wlp13s0` Wi-Fi interface and brings it down afterward; do not run it over your
only Wi-Fi connection. It expects `iw`, `wpa_supplicant`, and `curl` executables
under `~/.cache/shelly-provision/bin/`, plus `jq` and `ip` on PATH. Those tools
were prepared during the first plug's setup; check them if using a fresh machine.

If the cached executables are missing or their Nix store links have expired,
recreate just those tool links:

```bash
nix shell nixpkgs#iw nixpkgs#wpa_supplicant nixpkgs#curl -c bash -c '
  set -eu
  tools="$HOME/.cache/shelly-provision/bin"
  mkdir -p "$tools"
  for tool in iw wpa_supplicant curl; do
    ln -sfn "$(command -v "$tool")" "$tools/$tool"
  done
'
```

Replace the setup SSID below with the **second plug's exact SSID**:

```bash
AP_SSID='ShellyPlugMG3-REPLACE_WITH_NEW_PLUG_MAC'

systemd-run --user --wait --pipe --unit="shelly-provision-$(date +%s)" \
  /run/wrappers/bin/sudo -n env STATIC_IP=192.168.0.146 \
  bash /home/flakm/programming/flakm/nix_dots/scripts/shelly-provision.sh \
  --name 'Biuro PC' --ssid dom_iot --ap-ssid "$AP_SSID" \
  --psk-file "$HOME/.cache/shelly-provision/dom_iot.psk"
```

**The `STATIC_IP` override is essential:** the helper defaults to `.145`, which
belongs to the first plug. Always specify `--ap-ssid` to avoid targeting another
device. Run one provisioning session at a time.

The helper sets the device name, timezone, Wi-Fi credentials/static IP, disables
cloud, and disables the setup AP. **Its success message is not proof of pairing:**
the current helper does not validate Shelly RPC error objects, does not print
`restart_required`, and does not verify LAN/HA connectivity afterward. Complete
the remaining checks.

If it stops at `ERROR: WiFi scan returned nothing` right after bringing the
interface up, retry once. That first scan races with `ip link set up`: on
2026-10-21 it returned empty and the next attempt (seconds later) found the AP.
That error says nothing about the plug's radio.

### 3a. Reboot once before diagnosing anything

A static-IP `WiFi.SetConfig` does **not** take effect until the plug restarts.
On 2026-10-21 the helper reported success while the plug sat `disconnected` with
`sta_ip: 0.0.0.0` for about ten minutes. The stored config was correct: `dom_iot`
visible at −57 dBm and the same PSK verified independently from `wlp13s0`. One
reboot made it associate within seconds.

```bash
PLUG=192.168.0.146
curl --noproxy '*' --connect-timeout 3 --max-time 8 -fsS \
  "http://$PLUG/rpc/Shelly.Reboot"
```

Only reboot with **no PC attached** (check `Switch.GetStatus?id=0` reports
`output: false` and `apower: 0` via HTTP or BLE). Do this once, then run step 4.
Do not move APs, reset the plug, or change the WLAN in response to the
`disconnected` state — it is normally just the deferred restart.

If using the plug's local setup web UI instead, apply the same name, WLAN, and
reserved IP. Keep the consumption type as **switch**, not light. UI labels vary
by firmware. Configure the outbound HA connection in step 5 as well.

## 4. Confirm Wi-Fi association and the right device

Allow roughly **two minutes** for initial connection. The first plug's successful
reboot recovery took about 70 seconds; four seconds is not a useful failure cutoff.
The second plug associated within 10–20 seconds of the step 3a reboot.

In Omada, require an **active** client with the new MAC, `dom_iot`, and `.146`.
A known/inactive client or a stored reservation does not prove association.

```bash
PLUG=192.168.0.146

curl --noproxy '*' --connect-timeout 3 --max-time 8 -fsS \
  "http://$PLUG/rpc/Shelly.GetDeviceInfo" | jq .
curl --noproxy '*' --connect-timeout 3 --max-time 8 -fsS \
  "http://$PLUG/rpc/WiFi.GetStatus" | jq .
```

Require the expected device ID/MAC and name `Biuro PC`, then Wi-Fi status
`"got ip"`, SSID `dom_iot`, and `sta_ip: "192.168.0.146"`.
For newer firmware with HTTPS enabled, use its HTTPS endpoint and appropriate
certificate/authentication handling rather than assuming these HTTP commands apply.

## 5. Leave the outbound WebSocket disabled

Mains-powered plugs do **not** need an outbound WebSocket: Home Assistant talks
to them over the LAN. Manually enabling it makes HA 2026.5 create a repair,
**"Outbound WebSocket is enabled for <device>"**, whose fix disables it again.

HA enables the outbound WebSocket only for sleeping (battery) devices and manages
it itself. Do not run `Ws.SetConfig` on a plug.

If that repair appears anyway, use its **Submit** action. The fix reboots the
plug when `restart_required` is true, so when the plug powers a PC, wait until
the PC is off. Setting `enable: false` alone clears the repair immediately because
HA reads the stored config, even though the open connection survives until the
next reboot.

On 2026-10-21 both plugs had it enabled during setup and were later switched
back to `enable: false`; the repairs cleared without rebooting the office plug.
Do **not** include `"ssl_ca": null` in any `Ws.SetConfig` call: the firmware
rejects it.

## 6. Add to HA and verify control

1. In HA, go to **Settings → Devices & services** and configure the discovered
   Shelly device. If it is not discovered, **Add integration → Shelly**, host
   `192.168.0.146`. Do not add a duplicate entry if it already exists.
   An open outbound WebSocket does **not** register the device: on 2026-10-21
   `Ws.GetStatus` was `connected: true` while HA had no Shelly entry for it, so
   the manual add was required.
2. Confirm these entities exist and are not `unavailable`:
   - `switch.biuro_pc`
   - `sensor.biuro_pc_power`
   - `sensor.biuro_pc_energy`
3. If HA generated different IDs, align them with the existing names expected by
   `hosts/odroid/smart-plugs.nix`. Keep this device distinct from `Sypialnia dzieci`.
   Control the office plug through `switch.biuro_pc_gniazdko`, not the raw
   `switch.biuro_pc`: the template switch refuses to turn off while
   `sensor.biuro_pc_power` is above 30 W. The raw switch is hidden in the UI and
   is only used by `script.biuro_pc_wylacz_na_sile` (behind a confirmation).
4. Open [Gniazdka](https://homeassistant.house.flakm.com/smart-gniazdka/gniazdka).
   With **no PC attached**, test on/off using an empty plug or lamp. Confirm the
   physical relay responds and HA updates. For an idempotent test, send the current
   state again and check `Switch.GetStatus?id=0` reports `source: "WS_in"`.
5. Leave it connected for several minutes, then do one safe reboot/recovery test
   with no PC attached. Verify **HA control**, not just ping.
6. Only now attach the PC/monitor, turn the plug on, and verify power/energy readings.
   Set the electricity price in the dashboard. Do not copy the kids' light schedule
   to the office plug.

## Troubleshooting without repeating the first investigation

| Symptom | Next check |
|---|---|
| Helper stops at `ERROR: WiFi scan returned nothing` | Retry once; the first scan after `ip link set up` can return empty. This is a workstation race, not a plug problem. |
| Provisioned "successfully" but `WiFi.GetStatus` stays `disconnected` with `sta_ip: 0.0.0.0` | Reboot the plug once (step 3a). Static-IP `WiFi.SetConfig` needs a restart. Verify the PSK separately before blaming signal; do not move APs or reset the plug. |
| Cannot join setup AP / workstation scan is empty | Check `wlp13s0` and retry scanning; this alone says nothing about the plug's radio. Use a phone or BLE as an independent check. |
| Omada has no active client; plug says `connecting`/no IP | Wi-Fi association is failing **before HA pairing**. Try commissioning near jadalnia; if needed, one unplug/replug with no load. Inspect the actual failure before resetting or changing WLANs. |
| Plug is associated, but inbound HTTP times out | HA controls the plug over the LAN, so this must be fixed, not routed around. Keep the outbound WebSocket disabled; use BLE to verify the relay state while diagnosing. |
| HTTP works, but HA is unavailable | Check the HA Shelly entry, entity IDs, outbound server URL, and odroid's LAN port 8123. |
| `WiFi.Scan` appears to return `[]` | Inspect the **raw response** first. The old diagnostic discarded RPC errors and printed them as empty results; `-114` is a scan failure, not evidence of zero nearby networks. |
| `WiFi.GetConfig` does not expose `pass` | Normal: the password is write-only. Use `is_open` and compare the provisioned credential privately with Omada if necessary. |
| No firmware update is listed while offline | Recheck once online. The first plug then offered stable 2.1.0; do not assume an offline update check proves firmware is current. Updates require a separate decision, not a blind pairing retry. |

On the first plug, a capture from **piętro** showed successful Open System
authentication followed by AP **deauthentication reason 9** during association.
It subsequently worked through **jadalnia**. The exact cause is still unproven.
The second plug (`Biuro PC`) then associated on **piętro** at −52 dBm, on the
same `dom_iot` VAP, and recovered from two reboots without being moved; do not
treat piętro as unusable. The temporary 20 MHz test was reverted; **changing AP
channel width is not part of the established pairing procedure**. Do not reboot
APs, factory-reset plugs, change security settings, or lock clients to APs
without an explicit reason and approval for the disruption.

## Bluetooth (BLE) diagnostics

Use this when the plug has no LAN address, HTTP times out, or you need to check
the relay without touching the network. BLE RPC stays available while the plug is
connected to Wi-Fi (verified 2026-10-21 with the setup AP disabled), and read
calls do not disturb the relay or the PC.

### Find the BLE address

```bash
bluetoothctl --timeout 15 scan on | grep -i shelly
```

The advertised name is `ShellyPlugMG3-<WIFI_MAC>`. The BLE address is usually the
Wi-Fi MAC with the last byte +2 (`…35BC` → `…35BE`), but confirm it from the scan
name; never reuse the first plug's address.

### One-time setup on the workstation

```bash
python3 -m venv /tmp/opencode/shelly-venv
/tmp/opencode/shelly-venv/bin/pip install aioshelly bleak
systemctl is-active bluetooth
```

`aioshelly` handles the GATT framing; do not hand-roll the BLE protocol.

### Read-only probe

Save as `/tmp/opencode/ble_probe.py` and set `MAC` to the **new** device:

```python
import asyncio
from bleak import BleakScanner
from aioshelly.ble.provisioning import ble_rpc_device

MAC = "70:AF:09:FE:35:BE"

async def main():
    dev = await BleakScanner.find_device_by_address(MAC, timeout=25)
    if dev is None:
        print("not found")
        return 1
    async with ble_rpc_device(dev) as d:
        info = await d.call_rpc("Shelly.GetDeviceInfo")
        print("info:", {k: info.get(k) for k in ("id", "mac", "name", "model", "ver", "auth_en")})
        print("wifi:", await d.call_rpc("WiFi.GetStatus"))
        print("switch:", await d.call_rpc("Switch.GetStatus", {"id": 0}))
        print("ws:", await d.call_rpc("Ws.GetStatus"))
        print("methods:", len((await d.call_rpc("Shelly.ListMethods")).get("methods", [])))
    return 0

raise SystemExit(asyncio.run(main()))
```

```bash
/tmp/opencode/shelly-venv/bin/python /tmp/opencode/ble_probe.py
```

### Reading the result

- **Is it off?** `Switch.GetStatus` → `output: false`. `output: true` with
  `apower` near 0 means the relay is on but nothing draws power. Around 200 W
  means the PC is running: do not switch it off.
- **Did Wi-Fi work?** `WiFi.GetStatus` → `status: "got ip"`, `sta_ip`,
  `ssid`, `rssi`. `disconnected` with `sta_ip: 0.0.0.0` means association failed
  (see step 3a).
- **Is the outbound WebSocket off?** `Ws.GetConfig.enable` should be `false`.
  `Ws.GetStatus.connected` may still be `true` until the plug's next reboot: that
  is the old connection, not the stored flag.
- **Right device?** Compare `mac` with the Wi-Fi MAC; it is the same value.

### Discovering RPC methods

`Shelly.ListMethods` returns every method the firmware exposes (151 on
`1.8.99`), e.g. `Switch.GetStatus`, `Switch.Set`, `Switch.Toggle`,
`WiFi.GetConfig`, `Ws.SetConfig`, `Sys.SetConfig`, `Shelly.Reboot`.
`Shelly.GetComponents` lists component ids (`switch:0`, `wifi`, `cloud`, `ws`).
Call anything by name with its params:

```python
await d.call_rpc("Switch.GetStatus", {"id": 0})
await d.call_rpc("Shelly.GetStatus")
```

### Writes over BLE are live

`Switch.Set` with `{"id": 0, "on": false}` cuts power instantly, and
`Shelly.Reboot` reboots the plug. Never do either while the PC is attached.
Only one BLE client can connect at a time — close the Shelly app or any phone
connection first. When `auth_en` is `false` no password is needed.

Old `/tmp/opencode/ble_*.py` helpers target the **first plug**; do not run them
unchanged. BLE helpers, the venv, and PSK files may disappear; recreate them with
the steps above rather than depending on a previous session.

### Completion checklist

- [x] New device's Wi-Fi MAC and unique IP recorded/reserved.
- [x] Correct name, `dom_iot`, and active Omada client verified.
- [x] Cloud off; setup AP off after successful provisioning.
- [x] Outbound WebSocket left disabled; no HA repair raised.
- [x] Correct HA switch, power, and energy entities available.
- [x] HA relay command verified with a safe load; recovery after reboot verified.
- [x] First plug and the main Wi-Fi configuration left unchanged.
- [x] Final device ID/MAC/IP, AP, firmware, and any deviations recorded without secrets.

### Record — `Biuro PC` (2026-10-21)

| Field | Value |
|---|---|
| Device ID | `shellyplugmg3-70af09fe35bc` |
| Wi-Fi MAC | `70:AF:09:FE:35:BC` |
| BLE MAC | `70:AF:09:FE:35:BE` |
| Model / firmware | S3PL-30110EU / `1.8.99-plugmg3prod0` |
| IP / reservation | `192.168.0.146`, Omada reservation "Biuro PC" |
| AP / signal | `piętro` (`26:e1:5d:01:75:b5`), −52…−56 dBm |
| HA entities | `switch.biuro_pc` (hidden raw), `switch.biuro_pc_gniazdko` (safe proxy used by the dashboard), `sensor.biuro_pc_power`, `sensor.biuro_pc_energy` |
| Deviations | Helper needed a retry after an empty first scan; one reboot required after provisioning (static Wi-Fi config); outbound WebSocket was enabled during setup, then disabled to clear the HA "Outbound WebSocket is enabled" repair. HA did not auto-discover the device; it was added through the Shelly config flow. |
| Not done | Firmware update (1.8.99 → offered 2.1.0); attaching the PC; setting the real tariff (default 0.8 PLN/kWh). |
