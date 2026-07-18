# Odroid Router and Omada Bring-up

This runbook moves the odroid to the router profile and brings Omada switches
and access points online at site `Mieszka`.

`odroid-router` is the complete `odroid` configuration plus `router.nix`. It
retains all application services, storage, containers, backups, Home Assistant,
AdGuard, Omada, media services, Nextcloud, Paperless, Immich, Frigate,
Vaultwarden, Samba, Syncthing, and monitoring. Only networking changes: PPPoE,
LAN addressing, DHCP, NAT, DNS ownership, and WAN firewall policy.

The initial network is intentionally flat: untagged `192.168.0.0/24` only. Do
not enable guest, IoT, or other VLANs in Omada until matching router interfaces,
DHCP scopes, routing, and firewall policy exist in `router.nix`.

## Constants

Run Omada commands from `amd-pc`:

```sh
export SITE=Mieszka
export SITE_ID=6a5625e443af3348ff66a466
```

After discovery, set these from the device inventory. Omada expects MAC
addresses in hyphen-separated form.

```sh
export SWITCH_MAC=AA-BB-CC-DD-EE-FF
export AP_MAC=AA-BB-CC-DD-EE-FF
```

## 1. Build Before Moving Cables

From the repository root on `amd-pc`:

```sh
nix build --no-link .#nixosConfigurations.odroid-router.config.system.build.toplevel
```

Confirm interface names and MAC addresses on the odroid:

```sh
ssh flakm@odroid 'ip -br link show enp1s0 enp2s0'
ssh flakm@odroid 'cat /sys/class/net/enp1s0/address'
ssh flakm@odroid 'cat /sys/class/net/enp2s0/address'
```

Expected wiring:

- `enp1s0`, MAC `00:1e:06:45:2e:dc`: LAN switch
- `enp2s0`, MAC `00:1e:06:45:2e:dd`: bridged ISP modem or ONT

Confirm that the ISP handoff is bridged and whether PPPoE requires a tagged WAN
VLAN. The current configuration sends untagged PPPoE with MTU/MRU `1492`.

## 2. Prepare the Router Profile for the Move

Push the router commit, then configure the router profile for the next boot
without activating it at the old house:

```sh
git push
nixos-rebuild boot --target-host flakm@192.168.0.102 --use-remote-sudo --flake github:FlakM/nix_dots#odroid-router
ssh flakm@192.168.0.102 'sudo poweroff'
```

Do not reboot again at the old house. At the new house, boot the ONT first, wait
for synchronization, connect the ONT to `enp2s0`, connect the switch to
`enp1s0`, and then boot the odroid. Keep a local console and a laptop with
Ethernet available.

Monitor the odroid LAN address:

```sh
while true; do date; ping -c 1 192.168.0.102; sleep 2; done
```

Inspect the resulting network from the odroid console or over SSH:

```sh
sudo networkctl status enp1s0
sudo networkctl status enp2s0
ip -4 address show dev enp1s0
cat /sys/class/net/enp2s0/carrier
systemctl status pppd-wan --no-pager
ip -br address show ppp0
ip -4 route
ip route get 1.1.1.1
```

Expected results:

- `enp1s0` has both `192.168.0.1/24` and `192.168.0.102/24`.
- `enp2s0` carrier is `1`; it does not receive an IP address.
- `ppp0` has the ISP-assigned IPv4 address.
- The default route uses `ppp0`.

Interpret PPPoE failures before changing credentials:

- `Timeout waiting for PADO`: cabling, bridge mode, or required WAN VLAN.
- Authentication failure: username format or password.
- Carrier `0`: physical link or ONT problem.

Check required services:

```sh
sudo systemctl is-active systemd-networkd pppd-wan dnsmasq adguardhome nginx podman-omada-controller
sudo systemctl --no-pager --full status pppd-wan dnsmasq adguardhome podman-omada-controller
sudo journalctl -b -u systemd-networkd -u pppd-wan -u dnsmasq -u adguardhome -u podman-omada-controller --no-pager
```

Check forwarding, NAT, and listeners:

```sh
sysctl net.ipv4.ip_forward
sudo iptables -S nixos-filter-forward
sudo iptables -t nat -S
sudo ss -lntup
sudo ss -lunp '( sport = :67 )'
```

`net.ipv4.ip_forward` must be `1`. Omada should listen on TCP
`8043,8088,8843,29811-29816` and UDP `27001,29810`. Only `dnsmasq`
should listen on DHCP server port UDP `67`.

## 3. Validate a Wired Client

Connect one Linux client to the LAN and renew its lease:

```sh
export CLIENT_IF=enp1s0
sudo networkctl renew "$CLIENT_IF"
ip -4 address
ip -4 route
resolvectl status
```

Expected DHCP values:

- Address: `192.168.0.100` through `192.168.0.250`
- Gateway: `192.168.0.1`
- DNS server: `192.168.0.102`

Test routing and DNS:

```sh
ping -c 3 192.168.0.1
ping -c 3 192.168.0.102
ping -c 3 1.1.1.1
dig @192.168.0.102 cloudflare.com
dig @192.168.0.102 omada.house.flakm.com
curl -fsS https://omada.house.flakm.com/ >/dev/null
```

The local Omada name must resolve to `192.168.0.102`.

## 4. Correct Controller Security and Site Settings

The OpenAPI application currently has permission to read the site device
account, including its plaintext password. The password has appeared in command
output and must be considered exposed.

In the Omada UI:

1. Rotate the site device-account password under site device-account settings.
2. Restrict the application under **Global View > Settings > Platform
   Integration > Open API** to the narrowest role that supports device and
   client inspection.
3. Do not put the replacement device password in an `omada --json` argument;
   arguments are visible in process listings and shell history.

Set the correct timezone through OpenAPI:

```sh
omada updateSiteEntity --site "$SITE" --json '{"region":"Poland","scenario":"Home","timeZone":"Europe/Warsaw"}'
omada getSiteEntity --site "$SITE"
```

Verify that `result.timeZone` is `Europe/Warsaw`.

Refresh and verify CLI metadata:

```sh
omada auth
omada spec refresh
omada sites refresh
omada getSiteEntity --site "$SITE"
```

## 5. Back Up the Pre-adoption Site

Create a site backup before adoption:

```sh
omada backupSitesSelfServer --json "{\"siteIds\":[\"$SITE_ID\"]}"
omada getSiteBackupResult --site "$SITE"
omada getSelfServerSiteFileList --site "$SITE"
```

Do not continue until the backup result reports success and the file list is
non-empty.

## 6. Discover and Adopt Devices

Connect the Omada switch and APs to the untagged LAN. List pending devices:

```sh
omada getGridPendingDevicesBySite --site "$SITE" --page 1 --page-size 1000
```

For each device, record its name, model, MAC address, serial number, IP address,
and firmware. Adopt only one device at a time:

```sh
omada adoptDevice --site "$SITE" --device-mac "$SWITCH_MAC"
omada getDeviceAdoptResult --site "$SITE" --device-mac "$SWITCH_MAC"
omada getDeviceList --site "$SITE" --page 1 --page-size 1000
```

Repeat for each AP after the switch reports connected:

```sh
omada adoptDevice --site "$SITE" --device-mac "$AP_MAC"
omada getDeviceAdoptResult --site "$SITE" --device-mac "$AP_MAC"
omada getDeviceList --site "$SITE" --page 1 --page-size 1000
```

If a device does not appear, verify discovery traffic on the odroid:

```sh
nix shell nixpkgs#tcpdump -c sh -c 'sudo "$(command -v tcpdump)" -ni enp1s0 "udp port 29810 or udp port 27001"'
sudo ss -lnup | grep -E ':(27001|29810)\b'
sudo journalctl -f -u podman-omada-controller
```

Factory-reset a device only after confirming that it is not managed by another
controller whose configuration must be retained.

## 7. Inventory and Firmware

List all adopted devices:

```sh
omada getDeviceList --site "$SITE" --page 1 --page-size 1000
```

Check firmware for each device:

```sh
omada getFirmwareInfo --site "$SITE" --device-mac "$SWITCH_MAC"
omada getFirmwareInfo --site "$SITE" --device-mac "$AP_MAC"
```

Create another backup before upgrading:

```sh
omada backupSitesSelfServer --json "{\"siteIds\":[\"$SITE_ID\"]}"
omada getSiteBackupResult --site "$SITE"
```

Upgrade one device at a time. Start with an AP, not the only switch:

```sh
omada onlineUpgrade --site "$SITE" --device-mac "$AP_MAC"
omada getOnlineUpgradeRes --site "$SITE" --device-mac "$AP_MAC"
omada getDeviceList --site "$SITE" --page 1 --page-size 1000
```

Wait for the AP to return to connected state before upgrading another device.
Upgrade the switch last:

```sh
omada onlineUpgrade --site "$SITE" --device-mac "$SWITCH_MAC"
omada getOnlineUpgradeRes --site "$SITE" --device-mac "$SWITCH_MAC"
omada getDeviceList --site "$SITE" --page 1 --page-size 1000
```

## 8. Inspect the Switch

Read switch state, PoE state, and configured networks:

```sh
omada getSwitchInfo --site "$SITE" --switch-mac "$SWITCH_MAC"
omada getPoePortsList --site "$SITE"
omada listSwitchNetworks --site "$SITE" --switch-mac "$SWITCH_MAC"
omada getCableTestOswPorts --site "$SITE" --switch-mac "$SWITCH_MAC"
```

In the UI, name every used port and confirm:

- The odroid uplink and AP ports use the default untagged LAN.
- AP ports negotiate at their expected speed.
- PoE is enabled only where required.
- No loop or unexpected wireless mesh uplink exists.

Run a cable test only on a port that can be interrupted. Replace `1` with the
physical port number:

```sh
omada startCableTest --site "$SITE" --switch-mac "$SWITCH_MAC" --json '{"portList":[{"port":1}]}'
omada getCableTestFullResults --site "$SITE" --switch-mac "$SWITCH_MAC"
```

## 9. Inspect Access Points and Wi-Fi

Inspect each AP:

```sh
omada getOverviewDetail --site "$SITE" --ap-mac "$AP_MAC"
omada getGeneralConfig_2 --site "$SITE" --ap-mac "$AP_MAC"
omada getRadiosDetail --site "$SITE" --ap-mac "$AP_MAC"
omada getUplinkWiredDetail --site "$SITE" --ap-mac "$AP_MAC"
omada getApLldpConfig --site "$SITE" --ap-mac "$AP_MAC"
```

List WLAN groups and SSIDs without hard-coding the WLAN ID:

```sh
export WLAN_ID="$(omada getWlanGroupList --site "$SITE" | jq -r '.result[] | select(.primary).wlanId')"
omada getWlanGroupList --site "$SITE"
omada getSsidList --site "$SITE" --wlan-id "$WLAN_ID" --page 1 --page-size 1000
```

The existing primary WLAN currently contains SSID `dom` with VLAN support
disabled. In the UI, verify that it uses the default untagged network and
WPA2/WPA3 with a strong password. Do not configure a VLAN ID.

An RF scan interrupts service on the selected AP. Run it before relying on that
AP for connectivity:

```sh
omada triggerRadioFrequencyScanV2 --site "$SITE" --ap-mac "$AP_MAC" --json '{}'
omada getRFScanResultV2 --site "$SITE" --ap-mac "$AP_MAC"
```

An empty body asks the AP to scan all supported radios. For initial manual
tuning, use 20 MHz on 2.4 GHz and non-overlapping channels 1, 6, or 11. Choose
5/6 GHz channels and widths from the scan rather than guessing.

## 10. Validate Clients and Topology

Connect one wired and one wireless client, then run:

```sh
omada getGridActiveClients --site "$SITE" --page 1 --page-size 1000
omada getTopology --site "$SITE"
omada getDeviceList --site "$SITE" --page 1 --page-size 1000
```

From each client:

```sh
ip -4 address
ip -4 route
resolvectl status
ping -c 3 192.168.0.1
dig @192.168.0.102 cloudflare.com
curl -fsS https://omada.house.flakm.com/ >/dev/null
```

Confirm in AdGuard that the client generated DNS queries:

```sh
ssh flakm@odroid 'sudo journalctl -u adguardhome --since "10 minutes ago" --no-pager'
```

## 11. Add Infrastructure DHCP Reservations

Use addresses from `192.168.0.2` through `192.168.0.99`, outside the dynamic
pool. Add one line per switch or AP to `services.dnsmasq.settings.dhcp-host` in
`router.nix`:

```nix
"aa:bb:cc:dd:ee:ff,device-name,192.168.0.10,infinite"
```

Then rebuild and deploy:

```sh
nix build --no-link .#nixosConfigurations.odroid-router.config.system.build.toplevel
nixos-rebuild switch --target-host flakm@odroid --use-remote-sudo --flake .#odroid-router
```

Reconnect or reboot the device through the UI and confirm its reserved address:

```sh
omada getDeviceList --site "$SITE" --page 1 --page-size 1000
```

## 12. External Firewall Validation

Run these commands from outside the home LAN. Replace `PUBLIC_IP` with the
current WAN address:

```sh
export PUBLIC_IP=203.0.113.1
nix shell nixpkgs#nmap -c nmap -Pn -p 22,53,80,443,3000,8043,8088,8843,29811-29816 "$PUBLIC_IP"
nix shell nixpkgs#nmap -c nmap -Pn -sU -p 53,27001,29810 "$PUBLIC_IP"
```

All listed management, DNS, HTTP, HTTPS, and adoption ports must be closed or
filtered from WAN. Only UDP `41641` for Tailscale and UDP `51820` for WireGuard
are intentionally allowed by the host firewall.

Test Tailscale and WireGuard from an external network after the ordinary WAN
path works.

## 13. Restart Validation

Create a final backup, then reboot the odroid during a maintenance window:

```sh
omada backupSitesSelfServer --json "{\"siteIds\":[\"$SITE_ID\"]}"
omada getSiteBackupResult --site "$SITE"
ssh flakm@odroid 'sudo systemctl reboot'
```

After it returns:

```sh
ssh flakm@odroid 'systemctl is-active systemd-networkd dnsmasq adguardhome nginx podman-omada-controller'
omada auth
omada getDeviceList --site "$SITE" --page 1 --page-size 1000
omada getGridActiveClients --site "$SITE" --page 1 --page-size 1000
omada getTopology --site "$SITE"
```

All infrastructure should return to connected state without manual
provisioning.
