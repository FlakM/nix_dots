# Frigate recordings and evidence

## Normal access

Use [Frigate](https://frigate.house.flakm.com) rather than VNC. The web UI reads the recording database, joins the ten-second files into a timeline, and avoids exposing the ZFS dataset as a desktop filesystem.

- **Review**: alerts and detections, including the annotated snapshot and clip.
- **Explore**: saved object snapshots.
- **History**: continuous video for an arbitrary camera and time range.
- **Export**: preserved videos created from Review or History.

To preserve evidence, export it immediately: right-click a Review item on desktop or long-press it on mobile, then select **Export**. For a custom interval, open History and use **Export**. Download the resulting MP4 from the Export page and keep a separate copy.

## Retention

The configuration in `frigate.nix` currently keeps:

- all continuous recordings for 7 days;
- recording segments overlapping alerts or detections with motion for 90 days;
- annotated snapshots and clean snapshots for 90 days.

An export is safer than relying on retention. Frigate may also delete the oldest recording hour if free storage drops below one hour of estimated recording capacity.

## Storage layout

Live inspection on 2026-07-21 showed:

| Dataset | Mount | Used |
| --- | --- | ---: |
| `tank/data/frigate/recordings` | `/var/lib/frigate/recordings` | 318 GiB |
| `tank/data/frigate/clips` | `/var/lib/frigate/clips` | 489 MiB |
| `tank/data/frigate/exports` | `/var/lib/frigate/exports` | empty |

Raw recordings use this layout:

```text
/var/lib/frigate/recordings/YYYY-MM-DD/HH/<camera>/MM.SS.mp4
```

The path date and hour are UTC, not Europe/Warsaw local time. Each MP4 is approximately ten seconds. Frigate writes these files directly from each camera's main stream without re-encoding. Do not rename, move, or delete raw segments behind Frigate because its SQLite index will become inconsistent.

Snapshots are stored in `/var/lib/frigate/clips`:

```text
back-<event-id>.jpg          # timestamp and person bounding box
back-<event-id>-clean.webp  # full-resolution image without annotations
```

Review previews and thumbnails are below `/var/lib/frigate/clips/previews`, `/var/lib/frigate/clips/review`, and `/var/lib/frigate/clips/thumbs`. Exports are written to `/var/lib/frigate/exports`.

## Direct access

The `flakm` user belongs to the `frigate` group after the updated system configuration is activated and a new login session is started. This permits read access to recordings and snapshots over SSH.

List an hour of back-camera segments:

```bash
ssh odroid 'ls -lh /var/lib/frigate/recordings/2026-07-21/19/back'
```

Copy and play an export:

```bash
scp odroid:/var/lib/frigate/exports/<export>.mp4 .
mpv <export>.mp4
```

Copy an annotated event snapshot or its clean original:

```bash
scp 'odroid:/var/lib/frigate/clips/back-<event-id>.jpg' .
scp 'odroid:/var/lib/frigate/clips/back-<event-id>-clean.webp' .
```

Prefer a Frigate export over manually concatenating raw segments. An export records the intended time range in one playable file and avoids timestamp discontinuities between camera segments.

## Event API

When troubleshooting over SSH, the local unauthenticated API can list events and retrieve their media:

```bash
ssh odroid 'curl -fsS "http://127.0.0.1:5000/api/events?camera=back&label=person&limit=10"'
ssh odroid 'curl -fLo /tmp/event.jpg http://127.0.0.1:5000/api/events/<event-id>/snapshot.jpg'
ssh odroid 'curl -fLo /tmp/event.mp4 http://127.0.0.1:5000/api/events/<event-id>/clip.mp4'
scp odroid:/tmp/event.jpg odroid:/tmp/event.mp4 .
```

The public API at `https://frigate.house.flakm.com/api/...` requires Frigate authentication. Home Assistant notifications use its Frigate integration proxy and now display the annotated person image rather than an unrelated live frame.
