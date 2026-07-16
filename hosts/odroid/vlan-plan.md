# VLAN Migration Plan

This plan keeps routing, DHCP, DNS, NAT, and firewall policy on the odroid.
Omada manages only switch VLAN membership, port profiles, and SSID tagging.

Do not execute the mutation commands until the switch and APs are adopted,
connected, backed up, and their physical ports are known.

## Layout

| Network | VLAN | Subnet | Purpose |
| --- | ---: | --- | --- |
| Management | native/untagged | `192.168.0.0/24` | odroid, switch, AP management |
| Trusted | 10 | `192.168.10.0/24` | personal computers and phones |
| IoT | 20 | `192.168.20.0/24` | smart-home devices |
| Guest | 30 | `192.168.30.0/24` | internet-only guests |
| Cameras | 40 | `192.168.40.0/24` | cameras without internet access |

Keep management untagged during this migration. Moving management to a tagged
VLAN would require changing the router, switch, APs, and controller reachability
without a safe intermediate state.

## Firewall Policy

- Management can reach every VLAN.
- Trusted can reach every VLAN and the internet.
- IoT can reach the internet and odroid DNS/Home Assistant, but cannot initiate
  connections to Management, Trusted, Guest, or Cameras.
- Guest can reach odroid DNS and the internet only.
- Cameras can reach odroid DNS only and cannot initiate routed connections or
  reach the internet.
- Established replies are allowed for connections initiated from a permitted
  network.
- mDNS reflection is limited to Management, Trusted, and IoT.
- IPv6 remains disabled until equivalent IPv6 policy exists.

## 1. Add Secret-safe CLI Input

The current `omada` CLI accepts request bodies only through `--json`. WPA keys
would therefore appear in shell history and process arguments. Before creating
or updating SSIDs, add this interface to the CLI:

```text
--json-file <PATH>
--json-file -
```

`--json-file -` must read the body from standard input. Reject simultaneous
`--json` and `--json-file`. Verify that secrets do not appear in `ps` output.

Store the Trusted, IoT, Guest, and Cameras WPA keys as SOPS secrets. The later
commands refer to their decrypted paths as:

```sh
export TRUSTED_PSK_FILE=~/.config/sops-nix/secrets/wifi_trusted_psk
export IOT_PSK_FILE=~/.config/sops-nix/secrets/wifi_iot_psk
export GUEST_PSK_FILE=~/.config/sops-nix/secrets/wifi_guest_psk
export CAMERAS_PSK_FILE=~/.config/sops-nix/secrets/wifi_cameras_psk
```

## 2. Prepare the Odroid Router

Update `router.nix` before changing Omada:

1. Create `vlan10`, `vlan20`, `vlan30`, and `vlan40` systemd-networkd VLAN
   netdevs on `enp1s0`.
2. Assign `192.168.10.1/24`, `192.168.20.1/24`, `192.168.30.1/24`, and
   `192.168.40.1/24` respectively.
3. Add all VLAN interfaces to `networking.nat.internalInterfaces`.
4. Add dnsmasq DHCP ranges `.100` through `.250` for each subnet with the VLAN
   gateway as router and DNS server.
5. Keep `enp1s0` trusted. Trust `vlan10`, but do not trust `vlan20`, `vlan30`,
   or `vlan40`.
6. Permit DNS and DHCP input on all VLAN interfaces. Permit Home Assistant input
   from `vlan20` only where required.
7. Add explicit forward-chain policy matching the firewall policy above.
8. Enable Avahi reflection only on `enp1s0`, `vlan10`, and `vlan20`.

Build and deploy while Omada still uses only the untagged LAN:

```sh
nix build --no-link .#nixosConfigurations.odroid-router.config.system.build.toplevel
nixos-rebuild switch --target-host flakm@odroid --use-remote-sudo --flake .#odroid-router
```

Verify all VLAN interfaces before continuing:

```sh
ssh flakm@odroid 'networkctl status vlan10 vlan20 vlan30 vlan40'
ssh flakm@odroid 'ip -4 address show dev vlan10'
ssh flakm@odroid 'ip -4 address show dev vlan20'
ssh flakm@odroid 'ip -4 address show dev vlan30'
ssh flakm@odroid 'ip -4 address show dev vlan40'
ssh flakm@odroid 'sudo systemctl is-active dnsmasq adguardhome'
ssh flakm@odroid 'sudo iptables -t nat -S'
ssh flakm@odroid 'sudo iptables -S nixos-filter-forward'
```

## 3. Capture Omada State and Back Up

Run from `amd-pc`:

```sh
export SITE=Mieszka
export SITE_ID=6a5625e443af3348ff66a466
export WLAN_ID=6a5625e543af3348ff66a47f

omada auth
omada getDeviceList --site "$SITE" --page 1 --page-size 1000
omada getLanNetworkListV2 --site "$SITE" --page 1 --page-size 1000
omada getLanProfileList --site "$SITE" --page 1 --page-size 1000
omada getSsidList --site "$SITE" --wlan-id "$WLAN_ID" --page 1 --page-size 1000
omada backupSitesSelfServer --json "{\"siteIds\":[\"$SITE_ID\"]}"
omada getSiteBackupResult --site "$SITE"
omada getSelfServerSiteFileList --site "$SITE"
```

The current Omada `Default` network claims DHCP configuration, but there is no
Omada gateway. Do not create Omada interface networks. All new networks must use
`purpose: 0` and `application: 1`, making them switch-only VLAN definitions.

## 4. Create Omada VLAN Definitions

These commands do not alter any port until a profile is assigned:

```sh
omada createLanNetworkV2 --site "$SITE" --json '{"name":"Trusted","purpose":0,"vlan":10,"application":1,"igmpSnoopEnable":true,"mldSnoopEnable":false,"dhcpL2RelayEnable":false}'
omada createLanNetworkV2 --site "$SITE" --json '{"name":"IoT","purpose":0,"vlan":20,"application":1,"igmpSnoopEnable":true,"mldSnoopEnable":false,"dhcpL2RelayEnable":false}'
omada createLanNetworkV2 --site "$SITE" --json '{"name":"Guest","purpose":0,"vlan":30,"application":1,"igmpSnoopEnable":true,"mldSnoopEnable":false,"dhcpL2RelayEnable":false}'
omada createLanNetworkV2 --site "$SITE" --json '{"name":"Cameras","purpose":0,"vlan":40,"application":1,"igmpSnoopEnable":true,"mldSnoopEnable":false,"dhcpL2RelayEnable":false}'
```

Capture network IDs from the controller instead of hard-coding response IDs:

```sh
NETWORKS="$(omada getLanNetworkListV2 --site "$SITE" --page 1 --page-size 1000)"
export DEFAULT_NETWORK_ID="$(jq -r '.result.data[] | select(.name == "Default") | .id' <<<"$NETWORKS")"
export TRUSTED_NETWORK_ID="$(jq -r '.result.data[] | select(.name == "Trusted") | .id' <<<"$NETWORKS")"
export IOT_NETWORK_ID="$(jq -r '.result.data[] | select(.name == "IoT") | .id' <<<"$NETWORKS")"
export GUEST_NETWORK_ID="$(jq -r '.result.data[] | select(.name == "Guest") | .id' <<<"$NETWORKS")"
export CAMERAS_NETWORK_ID="$(jq -r '.result.data[] | select(.name == "Cameras") | .id' <<<"$NETWORKS")"
```

Stop if any variable is empty:

```sh
test -n "$DEFAULT_NETWORK_ID" \
  && test -n "$TRUSTED_NETWORK_ID" \
  && test -n "$IOT_NETWORK_ID" \
  && test -n "$GUEST_NETWORK_ID" \
  && test -n "$CAMERAS_NETWORK_ID" \
  && printf '%s\n' 'All network IDs found'
```

## 5. Create Switch Port Profiles

Create a router trunk with native Management and all client VLANs tagged:

```sh
omada createLanProfile --site "$SITE" --json "$(jq -nc \
  --arg native "$DEFAULT_NETWORK_ID" \
  --arg trusted "$TRUSTED_NETWORK_ID" \
  --arg iot "$IOT_NETWORK_ID" \
  --arg guest "$GUEST_NETWORK_ID" \
  --arg cameras "$CAMERAS_NETWORK_ID" \
  '{name:"Trunk-Router",nativeNetworkId:$native,tagNetworkIds:[$trusted,$iot,$guest,$cameras],bandWidthCtrlType:0,dot1x:1,lldpMedEnable:true,loopbackDetectEnable:true,poe:1,portIsolationEnable:false,spanningTreeEnable:true}')"
```

Create an AP trunk with the same VLANs and PoE enabled:

```sh
omada createLanProfile --site "$SITE" --json "$(jq -nc \
  --arg native "$DEFAULT_NETWORK_ID" \
  --arg trusted "$TRUSTED_NETWORK_ID" \
  --arg iot "$IOT_NETWORK_ID" \
  --arg guest "$GUEST_NETWORK_ID" \
  --arg cameras "$CAMERAS_NETWORK_ID" \
  '{name:"Trunk-AP",nativeNetworkId:$native,tagNetworkIds:[$trusted,$iot,$guest,$cameras],bandWidthCtrlType:0,dot1x:1,lldpMedEnable:true,loopbackDetectEnable:true,poe:0,portIsolationEnable:false,spanningTreeEnable:true}')"
```

Create untagged access profiles:

```sh
create_access_profile() {
  local name="$1" network_id="$2" isolated="$3"
  omada createLanProfile --site "$SITE" --json "$(jq -nc \
    --arg name "$name" \
    --arg native "$network_id" \
    --argjson isolated "$isolated" \
    '{name:$name,nativeNetworkId:$native,tagNetworkIds:[],untagNetworkIds:[],bandWidthCtrlType:0,dot1x:1,lldpMedEnable:true,loopbackDetectEnable:true,poe:2,portIsolationEnable:$isolated,spanningTreeEnable:true}')"
}

create_access_profile Access-Trusted "$TRUSTED_NETWORK_ID" false
create_access_profile Access-IoT "$IOT_NETWORK_ID" false
create_access_profile Access-Guest "$GUEST_NETWORK_ID" true
create_access_profile Access-Cameras "$CAMERAS_NETWORK_ID" true
```

Capture profile IDs:

```sh
PROFILES="$(omada getLanProfileList --site "$SITE" --page 1 --page-size 1000)"
export DEFAULT_PROFILE_ID="$(jq -r '.result.data[] | select(.name == "Default") | .id' <<<"$PROFILES")"
export ROUTER_TRUNK_ID="$(jq -r '.result.data[] | select(.name == "Trunk-Router") | .id' <<<"$PROFILES")"
export AP_TRUNK_ID="$(jq -r '.result.data[] | select(.name == "Trunk-AP") | .id' <<<"$PROFILES")"
export TRUSTED_ACCESS_ID="$(jq -r '.result.data[] | select(.name == "Access-Trusted") | .id' <<<"$PROFILES")"
export IOT_ACCESS_ID="$(jq -r '.result.data[] | select(.name == "Access-IoT") | .id' <<<"$PROFILES")"
export GUEST_ACCESS_ID="$(jq -r '.result.data[] | select(.name == "Access-Guest") | .id' <<<"$PROFILES")"
export CAMERAS_ACCESS_ID="$(jq -r '.result.data[] | select(.name == "Access-Cameras") | .id' <<<"$PROFILES")"
```

## 6. Apply Trunks Without Losing Management

Set the adopted switch MAC and physical port numbers from `getSwitchInfo` and
the cabling record:

```sh
export SWITCH_MAC=AA-BB-CC-DD-EE-FF
export ROUTER_PORT=1
export AP_PORT=2
export TEST_PORT=3
```

Apply the router trunk first. Its native network remains `Default`, so controller
management remains untagged:

```sh
omada setProfileForGivenPort_1 --site "$SITE" --switch-mac "$SWITCH_MAC" --port "$ROUTER_PORT" --json "{\"profileId\":\"$ROUTER_TRUNK_ID\"}"
omada getSwitchInfo --site "$SITE" --switch-mac "$SWITCH_MAC"
omada getDeviceList --site "$SITE" --page 1 --page-size 1000
ping -c 3 192.168.0.1
ping -c 3 192.168.0.102
```

Apply the AP trunk and verify the AP reconnects on untagged Management:

```sh
omada setProfileForGivenPort_1 --site "$SITE" --switch-mac "$SWITCH_MAC" --port "$AP_PORT" --json "{\"profileId\":\"$AP_TRUNK_ID\"}"
omada getDeviceList --site "$SITE" --page 1 --page-size 1000
omada getTopology --site "$SITE"
```

Rollback either port to the default untagged profile if management disappears:

```sh
omada setProfileForGivenPort_1 --site "$SITE" --switch-mac "$SWITCH_MAC" --port "$ROUTER_PORT" --json "{\"profileId\":\"$DEFAULT_PROFILE_ID\"}"
omada setProfileForGivenPort_1 --site "$SITE" --switch-mac "$SWITCH_MAC" --port "$AP_PORT" --json "{\"profileId\":\"$DEFAULT_PROFILE_ID\"}"
```

## 7. Validate Every Wired Access Profile

Assign one disposable test port to each profile, connect a laptop, renew DHCP,
and run the tests before moving real devices:

```sh
omada setProfileForGivenPort_1 --site "$SITE" --switch-mac "$SWITCH_MAC" --port "$TEST_PORT" --json "{\"profileId\":\"$TRUSTED_ACCESS_ID\"}"
```

On the test laptop, renew its lease and verify Trusted:

```sh
sudo networkctl renew enp1s0
ip -4 address show dev enp1s0
ip -4 route
dig @192.168.10.1 cloudflare.com
ping -c 3 192.168.0.102
ping -c 3 192.168.20.1
curl -fsS https://example.com/ >/dev/null
```

Repeat with `IOT_ACCESS_ID`; expect `192.168.20.0/24`, working DNS/internet,
and blocked access to Trusted and Management except explicitly permitted odroid
services:

```sh
omada setProfileForGivenPort_1 --site "$SITE" --switch-mac "$SWITCH_MAC" --port "$TEST_PORT" --json "{\"profileId\":\"$IOT_ACCESS_ID\"}"
```

Repeat with `GUEST_ACCESS_ID`; expect `192.168.30.0/24`, working DNS/internet,
and no access to any RFC1918 destination:

```sh
omada setProfileForGivenPort_1 --site "$SITE" --switch-mac "$SWITCH_MAC" --port "$TEST_PORT" --json "{\"profileId\":\"$GUEST_ACCESS_ID\"}"
```

Repeat with `CAMERAS_ACCESS_ID`; expect `192.168.40.0/24`, working local DNS,
no internet, and no camera-initiated inter-VLAN access:

```sh
omada setProfileForGivenPort_1 --site "$SITE" --switch-mac "$SWITCH_MAC" --port "$TEST_PORT" --json "{\"profileId\":\"$CAMERAS_ACCESS_ID\"}"
```

Restore the test port when done:

```sh
omada setProfileForGivenPort_1 --site "$SITE" --switch-mac "$SWITCH_MAC" --port "$TEST_PORT" --json "{\"profileId\":\"$DEFAULT_PROFILE_ID\"}"
```

## 8. Create VLAN-tagged SSIDs

These commands require the `--json-file -` prerequisite. They keep WPA keys out
of process arguments and write no plaintext temporary files.

Create WPA2/AES SSIDs on the APs:

```sh
create_psk_ssid() {
  local name="$1" vlan="$2" band="$3" guest="$4" key_file="$5"
  jq -nc \
    --arg name "$name" \
    --argjson vlan "$vlan" \
    --argjson band "$band" \
    --argjson guest "$guest" \
    --rawfile key "$key_file" \
    '{band:$band,broadcast:true,deviceType:1,enable11r:false,guestNetEnable:$guest,hidePwd:false,mloEnable:false,name:$name,pmfMode:2,security:3,vlanEnable:true,vlanId:$vlan,pskSetting:{encryptionPsk:3,gikRekeyPskEnable:false,securityKey:($key|rtrimstr("\n")),versionPsk:2}}' \
    | omada createSsid --site "$SITE" --wlan-id "$WLAN_ID" --json-file -
}

create_psk_ssid dom-iot 20 1 false "$IOT_PSK_FILE"
create_psk_ssid dom-guest 30 3 true "$GUEST_PSK_FILE"
create_psk_ssid dom-cameras 40 1 false "$CAMERAS_PSK_FILE"
```

`band: 1` is 2.4 GHz only for IoT/camera compatibility. `band: 3` is 2.4 and
5 GHz. Add a separate WPA3 SSID later if 6 GHz is required.

Migrate the existing `dom` SSID to Trusted only after the wired VLAN 10 test
passes. Capture its ID:

```sh
SSIDS="$(omada getSsidList --site "$SITE" --wlan-id "$WLAN_ID" --page 1 --page-size 1000)"
export DOM_SSID_ID="$(jq -r '.result.data[] | select(.name == "dom") | .ssidId' <<<"$SSIDS")"
```

Update it using the existing key from SOPS:

```sh
jq -nc \
  --rawfile key "$TRUSTED_PSK_FILE" \
  '{band:3,broadcast:true,enable11r:false,guestNetEnable:false,mloEnable:false,name:"dom",pmfMode:2,security:3,vlanEnable:true,vlanId:10,pskSetting:{encryptionPsk:3,gikRekeyPskEnable:false,securityKey:($key|rtrimstr("\n")),versionPsk:2}}' \
  | omada updateSsidBasicConfig --site "$SITE" --wlan-id "$WLAN_ID" --ssid-id "$DOM_SSID_ID" --json-file -
```

Verify without requesting secret-bearing SSID detail:

```sh
omada getSsidList --site "$SITE" --wlan-id "$WLAN_ID" --page 1 --page-size 1000
omada getGridActiveClients --site "$SITE" --page 1 --page-size 1000
```

## 9. Move Real Devices Gradually

1. Move personal wired ports to `Access-Trusted`.
2. Move IoT wired ports to `Access-IoT` and reconnect wireless IoT devices to
   `dom-iot`.
3. Move guest Wi-Fi use to `dom-guest`.
4. Move camera ports to `Access-Cameras`; use `dom-cameras` only for cameras
   that cannot be wired.
5. Verify Home Assistant discovery and control after each IoT device move.
6. Add only the minimum cross-VLAN exception needed for a device that fails.

Inspect clients and topology after each batch:

```sh
omada getGridActiveClients --site "$SITE" --page 1 --page-size 1000
omada getTopology --site "$SITE"
omada getDeviceList --site "$SITE" --page 1 --page-size 1000
```

## 10. Final Validation

From a Trusted client:

```sh
dig @192.168.10.1 cloudflare.com
ping -c 3 192.168.0.102
ping -c 3 192.168.20.1
ping -c 3 192.168.40.1
curl -fsS https://example.com/ >/dev/null
```

From IoT, Guest, and Cameras, verify the policy in the table rather than only
checking internet access. On the odroid, inspect counters while testing:

```sh
sudo iptables -L nixos-filter-forward -n -v
sudo iptables -t nat -L -n -v
sudo journalctl -u dnsmasq --since '10 minutes ago' --no-pager
```

Create a final backup after all devices are stable:

```sh
omada backupSitesSelfServer --json "{\"siteIds\":[\"$SITE_ID\"]}"
omada getSiteBackupResult --site "$SITE"
omada getSelfServerSiteFileList --site "$SITE"
```

Do not delete the untagged Management network or default profile. They are the
recovery path if a trunk or SSID configuration is wrong.
