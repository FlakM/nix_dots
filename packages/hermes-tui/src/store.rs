//! Small local side effects: bridge cache, clipboard and link opening.

use crate::config;
use serde_json::Value;
use std::io::Write;
use std::process::{Command, Stdio};

/// Unread notification count written by `hermes-bridge` for the quickshell panel.
pub fn unread() -> u64 {
    let path = config::cache_dir().join("bridge.json");
    let Ok(text) = std::fs::read_to_string(path) else {
        return 0;
    };
    let Ok(value) = serde_json::from_str::<Value>(&text) else {
        return 0;
    };
    value
        .get("unread")
        .and_then(Value::as_u64)
        .unwrap_or_default()
}

/// Last SSE event id persisted by `hermes-bridge`, so a fresh TUI does not
/// replay old notifications.
pub fn last_event_id() -> i64 {
    let path = config::cache_dir().join("last-event-id");
    std::fs::read_to_string(path)
        .ok()
        .and_then(|text| text.trim().parse().ok())
        .unwrap_or(0)
}

/// Open a link in the desktop browser without waiting for it.
pub fn open_url(url: &str) -> Result<(), String> {
    if url.trim().is_empty() {
        return Err("this thread has no link".to_string());
    }
    Command::new("xdg-open")
        .arg(url)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map(|_| ())
        .map_err(|error| format!("cannot open link: {error}"))
}

/// Copy text with whichever Wayland/X11 clipboard tool is installed.
pub fn copy_to_clipboard(text: &str) -> Result<(), String> {
    if text.trim().is_empty() {
        return Err("this thread has no link".to_string());
    }
    let candidates: &[(&str, &[&str])] = &[
        ("wl-copy", &[]),
        ("xclip", &["-selection", "clipboard"]),
        ("xsel", &["--clipboard", "--input"]),
    ];
    for (program, args) in candidates {
        let spawn = Command::new(program)
            .args(*args)
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
        if let Ok(mut child) = spawn {
            if let Some(mut stdin) = child.stdin.take() {
                let _ = stdin.write_all(text.as_bytes());
            }
            let _ = child.wait();
            return Ok(());
        }
    }
    Err("no clipboard tool found (tried wl-copy, xclip, xsel)".to_string())
}
