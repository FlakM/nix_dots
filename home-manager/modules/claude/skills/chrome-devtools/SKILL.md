---
name: chrome-devtools
description: Uses Chrome DevTools via MCP for efficient debugging, troubleshooting and browser automation. Use when debugging web pages, automating browser interactions, analyzing performance, or inspecting network requests. This skill does not apply to `--slim` mode (MCP configuration).
---

## Core Concepts

**Browser lifecycle**: Browser starts automatically on first tool call using a persistent Chrome profile. Configure via CLI args in the MCP server configuration: `npx chrome-devtools-mcp@latest --help`.

**Page selection**: Tools operate on the currently selected page. Use `list_pages` to see available pages, then `select_page` to switch context.

**Element interaction**: Use `take_snapshot` to get page structure with element `uid`s. Each element has a unique `uid` for interaction. If an element isn't found, take a fresh snapshot - the element may have been removed or the page changed.

## Workflow Patterns

### Before interacting with a page

1. Navigate: `navigate_page` or `new_page`
2. Wait: `wait_for` to ensure content is loaded if you know what you look for.
3. Snapshot: `take_snapshot` to understand page structure
4. Interact: Use element `uid`s from snapshot for `click`, `fill`, etc.

### Efficient data retrieval

- Use `filePath` parameter for large outputs (screenshots, snapshots, traces)
- Use pagination (`pageIdx`, `pageSize`) and filtering (`types`) to minimize data
- Set `includeSnapshot: false` on input actions unless you need updated page state

### Tool selection

- **Automation/interaction**: `take_snapshot` (text-based, faster, better for automation)
- **Visual inspection**: `take_screenshot` (when user needs to see visual state)
- **Additional details**: `evaluate_script` for data not in accessibility tree

### Parallel execution

You can send multiple tool calls in parallel, but maintain correct order: navigate → wait → snapshot → interact.

## Headed Mode on NixOS / Wayland

The MCP default (`--autoConnect`) launches headless Chrome. To get a **visible** browser window:

### 1. Launch headed Chrome with remote debugging

```bash
DISPLAY=:0 WAYLAND_DISPLAY=wayland-1 \
  $(which google-chrome-stable) \
  --remote-debugging-port=9222 \
  --user-data-dir=/tmp/chrome-headed-profile \
  --no-first-run \
  --no-default-browser-check \
  "https://example.com" > /tmp/chrome.log 2>&1 &
```

> Use the regular `google-chrome-stable` binary (not `google-chrome-wayland`) — the wayland-specific build always reports as HeadlessChrome even without `--headless`.
> The binary must be from the versioned non-wayland Nix package (e.g. `pkgs.google-chrome`), not `pkgs.google-chrome-wayland`.

### 2. Point MCP's autoConnect at the running Chrome

`--autoConnect` reads `~/.config/google-chrome/DevToolsActivePort` to find Chrome. After Chrome starts, write the correct port/browser-ID there:

```bash
WS_PATH=$(curl -s http://localhost:9222/json/version | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d['webSocketDebuggerUrl'].replace('ws://localhost:9222',''))")
mkdir -p ~/.config/google-chrome
printf "9222\n%s" "$WS_PATH" > ~/.config/google-chrome/DevToolsActivePort
```

Then call `list_pages` — the MCP will connect to the headed Chrome. The browser window stays open for manual interaction.

## Troubleshooting

If `chrome-devtools-mcp` is insufficient, guide users to use Chrome DevTools UI:

- https://developer.chrome.com/docs/devtools
- https://developer.chrome.com/docs/devtools/ai-assistance

If there are errors launching `chrome-devtools-mcp` or Chrome, refer to https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/troubleshooting.md.
