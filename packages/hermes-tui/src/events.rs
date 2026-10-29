//! Reconnecting SSE subscription.
//!
//! The thread never returns while the app runs: it reconnects with exponential
//! backoff, resumes from the last seen event id and reports connectivity so the
//! tab bar can show an offline banner.

use crate::api::{self, Api};
use crate::app::AppEvent;
use serde_json::Value;
use std::io::{BufRead, BufReader};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

pub fn spawn(api: Api, since: i64, tx: Sender<AppEvent>, stop: Arc<AtomicBool>) {
    let _ = thread::Builder::new()
        .name("hermes-sse".to_string())
        .spawn(move || run(api, since, tx, stop));
}

fn run(api: Api, mut since: i64, tx: Sender<AppEvent>, stop: Arc<AtomicBool>) {
    let agent = api::stream_agent();
    let mut backoff = 1u64;
    let mut first_attempt = true;

    while !stop.load(Ordering::Relaxed) {
        let url = format!("{}/api/events?since={}&format=sse", api.base(), since);
        let auth = format!("Bearer {}", api.token());
        let result = agent.get(&url).header("Authorization", &auth).call();

        match result {
            Ok(response) if response.status().is_success() => {
                first_attempt = false;
                backoff = 1;
                let _ = tx.send(AppEvent::Stream {
                    connected: true,
                    error: None,
                });
                let reader = BufReader::new(response.into_body().into_reader());
                stream_events(reader, &tx, &stop, &mut since);
                if stop.load(Ordering::Relaxed) {
                    return;
                }
                let _ = tx.send(AppEvent::Stream {
                    connected: false,
                    error: Some("event stream closed".to_string()),
                });
            }
            Ok(response) => {
                let status = response.status().as_u16();
                let mut message = format!("events endpoint returned HTTP {status}");
                if status == 401 || status == 403 {
                    message.push_str(" (check the API token)");
                }
                let _ = tx.send(AppEvent::Stream {
                    connected: false,
                    error: Some(message),
                });
            }
            Err(error) => {
                let _ = tx.send(AppEvent::Stream {
                    connected: false,
                    error: Some(format!("event stream: {error}")),
                });
            }
        }

        if stop.load(Ordering::Relaxed) {
            return;
        }
        let wait = if first_attempt { 1 } else { backoff };
        first_attempt = false;
        // Sleep in small slices so quitting does not wait for the full backoff.
        for _ in 0..wait * 10 {
            if stop.load(Ordering::Relaxed) {
                return;
            }
            thread::sleep(Duration::from_millis(100));
        }
        backoff = (backoff * 2).min(30);
    }
}

fn stream_events(
    mut reader: BufReader<impl std::io::Read>,
    tx: &Sender<AppEvent>,
    stop: &Arc<AtomicBool>,
    since: &mut i64,
) {
    let mut event_id: Option<i64> = None;
    let mut data = String::new();
    let mut line = String::new();

    loop {
        if stop.load(Ordering::Relaxed) {
            return;
        }
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) => return,
            Ok(_) => {}
            Err(_) => return,
        }
        let line = line.trim_end_matches(['\r', '\n']);
        if line.is_empty() {
            if !data.is_empty() {
                if let Some(event) = parse_event(&data, event_id) {
                    if let Some(id) = event.get("id").and_then(Value::as_i64) {
                        *since = (*since).max(id);
                    }
                    let _ = tx.send(AppEvent::Server(event));
                }
                data.clear();
            }
            event_id = None;
            continue;
        }
        if line.starts_with(':') {
            // ": keepalive" comment emitted every 20s by the server.
            continue;
        }
        if let Some(rest) = line.strip_prefix("data:") {
            data.push_str(rest.strip_prefix(' ').unwrap_or(rest));
            data.push('\n');
        } else if let Some(rest) = line.strip_prefix("id:") {
            event_id = rest.trim().parse().ok();
        }
    }
}

fn parse_event(data: &str, event_id: Option<i64>) -> Option<Value> {
    let trimmed = data.trim_end();
    if trimmed.is_empty() {
        return None;
    }
    let mut event = match serde_json::from_str::<Value>(trimmed) {
        Ok(Value::Object(object)) => Value::Object(object),
        Ok(other) => {
            let mut object = serde_json::Map::new();
            object.insert("type".to_string(), Value::String("unknown".to_string()));
            object.insert("payload".to_string(), other);
            Value::Object(object)
        }
        Err(_) => {
            let mut object = serde_json::Map::new();
            object.insert("type".to_string(), Value::String("unknown".to_string()));
            object.insert("payload".to_string(), serde_json::json!({ "raw": trimmed }));
            Value::Object(object)
        }
    };
    let object = event.as_object_mut()?;
    if !object.contains_key("id") {
        if let Some(id) = event_id {
            object.insert("id".to_string(), serde_json::json!(id));
        }
    }
    object
        .entry("type")
        .or_insert_with(|| Value::String("unknown".to_string()));
    object
        .entry("payload")
        .or_insert_with(|| Value::Object(serde_json::Map::new()));
    Some(event)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_an_event_frame_and_fills_the_id() {
        let event = parse_event(
            "{\"type\":\"job.step\",\"payload\":{\"job_id\":\"j1\"}}\n",
            Some(17),
        )
        .unwrap();
        assert_eq!(event["type"], "job.step");
        assert_eq!(event["id"], 17);
    }

    #[test]
    fn wraps_non_object_frames() {
        let event = parse_event("\"hello\"", None).unwrap();
        assert_eq!(event["type"], "unknown");
        assert_eq!(event["payload"], "hello");
    }
}
