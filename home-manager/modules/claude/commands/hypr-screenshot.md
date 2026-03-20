Take a screenshot of a Hyprland window and display it.

## Arguments
$ARGUMENTS - window class or title substring to match (e.g. "firefox", "slack", "kitty"). If empty, list available windows and ask the user which one to capture.

## Steps

1. If no argument provided, list windows:
   ```bash
   hyprctl clients -j | jq -r '.[] | select(.size[0] > 0) | "\(.class)\t\(.title)"'
   ```
   Then ask the user which window to capture.

2. Capture the window:
   ```bash
   geometry=$(hyprctl clients -j | jq -r \
     --arg q "<query>" \
     '[.[] | select(((.class | test($q; "i")) or (.title | test($q; "i"))) and .size[0] > 0)] |
      first | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
   grim -g "$geometry" /tmp/hypr-screenshot.png
   ```

3. Read `/tmp/hypr-screenshot.png` using the Read tool to display the image.

## Notes
- Windows on inactive workspaces have size `[0, 0]` and cannot be captured. Filter them out.
- If multiple windows match, pick the first visible one.
- `grim` and `jq` must be available (they are via nix profile).
