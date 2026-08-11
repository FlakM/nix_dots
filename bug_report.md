# Firefox browser chrome text intermittently disappears on native Wayland

> **RESOLVED 2026-08-10 — root cause found.** See "Root cause" at the bottom.
> It was never a rendering bug: Firefox snapshots the XDG desktop portal
> Settings at startup, and when `xdg-desktop-portal-gtk` cannot answer, the
> portal router replies with an *empty settings dictionary* which Firefox
> applies as a valid look-and-feel — leaving the chrome with no usable UI
> font. Every rendering-layer experiment below was a red herring.

## Summary

Firefox intermittently stops rendering text in its browser chrome under native Wayland on Hyprland. Tab titles, address-bar text, and other browser UI text disappear, while webpage content continues to render normally.

The problem has reproduced across Firefox versions, profiles, rendering preferences, and two Hyprland builds. XWayland renders correctly, but using XWayland is not an acceptable workaround.

The problem still occurs with both:

- Hyprland PR #15718's DMA-BUF damage fix.
- Firefox's DMA-BUF backend disabled with `widget.dmabuf.enabled=false`.

## Expected behavior

Firefox browser chrome text should remain visible under native Wayland.

## Actual behavior

- Browser chrome text intermittently disappears.
- Webpage text remains visible.
- The problem may not be present immediately after Firefox starts, but returns later.
- XWayland does not exhibit the problem.

## Environment

- NixOS 26.05
- Kernel 6.12.97
- Hyprland 0.56.0
- Firefox 153.0
- Firefox ESR 140 also reproduced the problem.
- Mesa 26.1.5
- AMD `radeonsi` renderer
- Monitor: 5120x1440 at 143.98 Hz over DisplayPort
- Firefox runs as a native Wayland client with `MOZ_ENABLE_WAYLAND=1`.
- `hyprctl clients -j` reports Firefox with `xwayland=false`.

The currently tested Hyprland build reports:

```text
Hyprland 0.56.0
commit 3125efd8d74a5adf66b5320aa08801f3ecf3db1c
Aquamarine 0.14.0
```

The currently tested Firefox process is:

```text
/nix/store/1q4vq1jmd8fq7px4s110710p51g4bdpm-firefox-153.0/lib/firefox/firefox
```

## Reproduction and isolation

The following cases reproduced the missing browser chrome text:

- Firefox 153 with the normal profile.
- Firefox 153 with pristine profiles.
- Firefox ESR 140 with a pristine profile.
- Native Wayland with the normal Firefox hardware-accelerated path.
- Native Wayland after forcing Skia canvas and content rendering.
- Native Wayland after removing all legacy rendering, media, popup, and `userChrome` customizations.
- Native Wayland after removing the forced Wayland VA-API environment variable.
- Native Wayland with Hyprland PR #15718 applied.
- Native Wayland with Firefox DMA-BUF disabled.

The following case rendered correctly:

- Firefox under XWayland.

This strongly isolates the problem to Firefox's native Wayland presentation path or its interaction with Hyprland, but it is not limited to Firefox DMA-BUF buffers.

## Investigation history

### Legacy profile and Skia

The profile previously contained legacy rendering and UI customization. Firefox 153 initially appeared related to a Cairo canvas preference, so these settings were tried:

```nix
"gfx.canvas.azure.backends" = "skia";
"gfx.content.azure.backends" = "skia";
```

They did not eliminate the problem and were removed.

Relevant commits:

- `eabc8a7` `firefox: fix missing browser chrome text`
- `1d6c844` `firefox: force Skia content rendering`
- `aed798d` `firefox: stop forcing Skia rendering`

### Removed profile customizations

All nonessential Firefox profile customizations were removed, including:

- Forced VA-API and RDD media preferences.
- AV1 overrides.
- `widget.wayland.use-move-to-rect=false`.
- `widget.wayland.fractional-scale.enabled=false`.
- The `tabs_on_bottom.css` `userChrome` import.

The problem reproduced with pristine profiles, proving that the normal profile and its backups were not the cause.

Relevant commit:

- `3064041` `firefox: remove profile customizations`

### VA-API and video path

The global `MOZ_WAYLAND_USE_VAAPI=1` override was removed. This did not fix the missing chrome text.

Relevant commit:

- `5bd289d` `firefox: stop forcing Wayland VA-API`

### Wayland HDR

Firefox produced green video artifacts through its Wayland HDR path. Setting the following fixed the green video problem:

```nix
"gfx.wayland.hdr" = false;
```

This is still enabled, but it did not fix the missing browser chrome text.

Relevant commit:

- `b7e9f18` `firefox: disable broken Wayland HDR path`

### Hyprland DMA-BUF damage fix

Hyprland PR [#15718](https://github.com/hyprwm/Hyprland/pull/15718), `buffer: dont drop damage until actually read`, specifically describes Firefox attaching a DMA-BUF with damage and later committing a frame after the damage had already been cleared.

The PR head was pinned and deployed:

```nix
hyprland.url = "git+https://github.com/hyprwm/Hyprland?rev=3125efd8d74a5adf66b5320aa08801f3ecf3db1c&submodules=1";
```

The running compositor was verified to use `3125efd8d74a5adf66b5320aa08801f3ecf3db1c`. Firefox was verified as a native Wayland client. The problem returned anyway.

The PR was subsequently merged upstream as `4ffd88e5e6723c8d66ee214b96796d4c51cab7c1`. The tested revision is the PR head rather than the merge commit, but it contains the same relevant five-file damage-tracking patch.

Relevant commit:

- `2c48971` `hyprland: pin Firefox damage fix`

### Disabled Firefox DMA-BUF

Because the Hyprland damage fix was insufficient, Firefox's DMA-BUF backend was disabled while retaining native Wayland:

```nix
"widget.dmabuf.enabled" = false;
```

This preference exists in Firefox 153 and is read once at startup. It was verified in both Home Manager's generated `user.js` and the live profile's `prefs.js`:

```text
user_pref("widget.dmabuf.enabled", false);
```

Firefox was fully terminated and relaunched. It remained a native Wayland client with `xwayland=false`. Browser chrome text was initially visible after restart, but the problem returned.

Relevant commit:

- `b9ac90a` `firefox: disable broken DMA-BUF buffers`

## Current Firefox configuration

`home-manager/modules/firefox.nix` currently contains only these rendering workarounds:

```nix
settings = {
  "gfx.wayland.hdr" = false;
  "widget.dmabuf.enabled" = false;
};
```

The environment still intentionally forces native Wayland:

```nix
MOZ_ENABLE_WAYLAND = 1;
GDK_BACKEND = "wayland";
```

## Current conclusions

- This is not caused by the existing Firefox profile or `userChrome` CSS.
- This is not specific to Firefox 153 because ESR 140 also reproduces it.
- This is not fixed by selecting Skia rendering.
- This is not fixed by removing forced VA-API settings.
- This is not fixed by disabling Firefox's Wayland HDR path.
- This is not fixed by Hyprland PR #15718's DMA-BUF damage handling.
- This is not fixed by disabling Firefox's DMA-BUF backend.
- The issue remains specific to native Wayland in the tested environment because XWayland renders correctly.

## Useful artifacts

Prior test screenshots and logs are under `/tmp` with names including:

```text
firefox-clean.png
firefox-default.png
firefox-esr-native.png
firefox-pristine.png
firefox-pristine-cairo.png
firefox-pristine-skia.png
firefox-pristine-software.png
firefox-pristine-x11.png
firefox-managed-xwayland.png
firefox-dmabuf-disabled.png
```

Hyprland's active session log is under:

```text
/run/user/1000/hypr/<instance-signature>/hyprland.log
```

## Root cause (2026-08-10)

Firefox reads the whole GTK look-and-feel (UI font, sizes, colors) through
`org.freedesktop.portal.Settings.ReadAll` **once, early at process startup**.
On this setup the read is unconditional: it happens on Wayland regardless of
`GTK_USE_PORTAL` and before `widget.use-xdg-desktop-portal.settings` from the
profile can apply (all three opt-out combinations were tested and none
prevented the call — verified with `dbus-monitor`).

When `xdg-desktop-portal-gtk` cannot answer, `xdg-desktop-portal` does **not**
return an error — it replies *success with an empty `a{sa{sv}}`* (captured on
the bus). Firefox applies the empty snapshot as a valid look-and-feel and the
chrome is left without a usable UI font: tab titles, urlbar text and menu text
render as nothing, while page content (CSS-specified fonts via fontconfig) is
unaffected. The broken state persists for the lifetime of the process, which
is why a Firefox restart "randomly" fixes or reintroduces it.

### Proven trigger conditions

1. **Login race** — journal for the affected boot shows
   `Started firefox.` and `Started Portal service (GTK/GNOME implementation).`
   in the *same second* (08:52:11). The autostarted Firefox lost the race and
   ran with invisible chrome text from boot until manually restarted.
2. **Portal backend unable to start** — anything that leaves
   `xdg-desktop-portal-gtk` crash-looping reproduces the bug 100%
   deterministically on every new Firefox launch. Observed concrete cause: a
   second Hyprland instance (nested, or a stale greetd session) overwrites
   `WAYLAND_DISPLAY` in the systemd user environment; portal-gtk then dies
   with `cannot open display:` on its next (re)activation and hits its start
   limit.

Reproducer (safe, reversible):

```bash
systemctl --user set-environment WAYLAND_DISPLAY=wayland-dead
systemctl --user stop xdg-desktop-portal-gtk        # dbus reactivation now crash-loops
firefox --new-instance --profile $(mktemp -d)       # -> chrome text missing
systemctl --user set-environment WAYLAND_DISPLAY=wayland-1
systemctl --user reset-failed xdg-desktop-portal-gtk
systemctl --user start xdg-desktop-portal-gtk       # new launches healthy again
```

### Why the earlier evidence pointed away from rendering

- Reproduced with software WebRender → not the GPU driver.
- Did not reproduce under nested sway or nested default-config Hyprland →
  those tests ran while the host portal happened to be healthy.
- "XWayland was fine" was coincidence of timing, not backend.
- Hyprland damage fix, dmabuf, Skia, VA-API, HDR: all irrelevant (the
  `widget.dmabuf.enabled` workaround has been reverted).

### Fix applied

`home-manager/modules/hyprland.nix` now autostarts Firefox through
`firefox-after-portals`, which polls `Settings.ReadAll` via `busctl` until the
gtk backend serves real keys (`font-name`) before exec'ing Firefox. This
closes the login race, the only trigger that occurs in normal operation.

### Remaining upstream issues (worth filing)

- **xdg-desktop-portal**: `Settings.ReadAll` returns success with an empty
  dict when the backend implementation is unavailable instead of an error.
- **Firefox**: an empty `ReadAll` reply is applied as a valid look-and-feel
  instead of falling back to direct GTK/gsettings values.

### Hygiene note

If chrome text ever disappears again, first check:

```bash
systemctl --user status xdg-desktop-portal-gtk
systemctl --user show-environment | grep WAYLAND_DISPLAY   # must be wayland-1
busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
  org.freedesktop.portal.Settings ReadAll as 1 "org.gnome.desktop.interface" | head -c 200
```

then restart Firefox after the portal is healthy.
