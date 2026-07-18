# Screen Light Findings

- `amd-pc` does not expose a real screen backlight through `brightnessctl`; it only lists LED devices like keyboard lock LEDs and LAN LEDs.
- The active screen is an LG Ultrawide on `DP-1`, and it supports DDC/CI brightness control through `ddcutil`.
- Current monitor brightness was `100/100` from `ddcutil getvcp 10`.
- Existing Hyprland bindings used raw DDC commands: `SHIFT+F12` increased brightness by 10 and `SHIFT+F11` decreased it by 10.
- A smarter default is a small wrapper command that uses DDC when available and falls back to `brightnessctl --class=backlight` on laptops.
- The wrapper should operate in percentages, clamp to a minimum brightness, and show a notification with the resulting level.
- Useful bindings: hardware brightness keys plus the existing `SHIFT+F11/F12` fallback.

Proposed behavior:

- `screen-light up`: increase brightness by 5%.
- `screen-light down`: decrease brightness by 5%.
- `screen-light set PERCENT`: set an exact brightness percentage.
- `screen-light get`: show the current brightness percentage.

This keeps the desktop monitor path fast and explicit while still working on machines with a proper laptop backlight device.
