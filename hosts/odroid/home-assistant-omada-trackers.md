# Home Assistant Omada trackers

Home Assistant uses the `tplink_omada` integration to create presence trackers
for wireless clients known to the Omada controller. Newly discovered trackers
are disabled by default.

## Current ownership

| Device | Home Assistant entity | Person |
| --- | --- | --- |
| Pixel 7 | `device_tracker.pixel_7` | Maciek |
| Galaxy S24 | `device_tracker.galaxy_s24` | Patrycja |

Keep each phone's randomized Wi-Fi MAC stable for the `dom` network. Changing
or rotating that MAC makes Omada and Home Assistant treat the phone as a new
device.

## Enable a new tracker

1. Connect the device to the `dom` Wi-Fi network.
2. Give the client a recognizable name in Omada.
3. Wait for the Home Assistant Omada integration to poll the controller. The
   default interval is five minutes.
4. In Home Assistant, open **Settings > Devices & services > Entities**.
5. Search for the Omada client name and include disabled entities in the
   search.
6. Open the matching `device_tracker` entity and enable it.
7. Verify that its state changes between `home` and `not_home` when the device
   connects and disconnects.

If the tracker does not appear, reload **TP-Link Omada** under **Settings >
Devices & services**, then check the entity list again.

## Assign a tracker to a person

1. Open **Settings > People**.
2. Select the person or create them if they do not exist.
3. Under tracked devices, add the appropriate `device_tracker` entity.
4. Remove obsolete trackers for replaced devices.
5. Save and verify the resulting `person` entity state.

Assign `device_tracker.pixel_7` to Maciek and
`device_tracker.galaxy_s24` to Patrycja. Do not assign infrastructure clients,
cameras, televisions, or another person's devices to a person.

## Replace or remove a tracker

1. Enable and verify the replacement tracker first.
2. Add the replacement to the relevant person.
3. Remove the old tracker from that person.
4. Disable the old entity under **Settings > Devices & services > Entities**.
5. Delete the entity only when its history and entity ID are no longer useful.

## Configuration

- Integration package: `tplink_omada` in `hosts/odroid/home-assistant.nix`
- Omada account: `homeassistant`, with Viewer access to the `Mieszka` site
- Credentials: `omada_ha_username` and `omada_ha_password` in
  `secrets/secrets.yaml`

The standard integration reports only `home` and `not_home`. It does not expose
the access point associated with a client, so AP-based room or floor location
requires a separate OpenAPI-backed sensor or custom integration.
