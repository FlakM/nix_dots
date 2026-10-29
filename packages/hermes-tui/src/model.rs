//! Normalisation of API payloads into the flat shapes the UI renders.
//!
//! The agent returns a superset of fields depending on how far `tracking.describe`
//! has evolved; every accessor here is defensive and falls back instead of
//! panicking, because a desktop client must never break on a new payload.

use chrono::{Local, TimeZone, Timelike};
use serde_json::Value;
use std::collections::HashSet;

pub fn as_f64(value: Option<&Value>) -> Option<f64> {
    match value? {
        Value::Number(number) => number.as_f64(),
        Value::String(text) => text.trim().parse().ok(),
        _ => None,
    }
}

pub fn as_i64(value: Option<&Value>) -> Option<i64> {
    match value? {
        Value::Number(number) => number.as_i64(),
        Value::String(text) => text.trim().parse().ok(),
        Value::Bool(flag) => Some(i64::from(*flag)),
        _ => None,
    }
}

pub fn as_text(value: Option<&Value>) -> String {
    match value {
        Some(Value::String(text)) => text.clone(),
        Some(Value::Number(number)) => number.to_string(),
        Some(Value::Bool(flag)) => flag.to_string(),
        Some(Value::Null) | None => String::new(),
        Some(other) => other.to_string(),
    }
}

pub fn one_line(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

pub fn truncate(value: &str, width: usize) -> String {
    if width == 0 {
        return String::new();
    }
    let count = value.chars().count();
    if count <= width {
        return value.to_string();
    }
    if width <= 1 {
        return "…".to_string();
    }
    let mut out: String = value.chars().take(width - 1).collect();
    out.push('…');
    out
}

/// Compact age/cadence: `now`, `12m`, `5h`, `3d`, `2w`.
pub fn fmt_duration(seconds: Option<f64>) -> String {
    let Some(seconds) = seconds else {
        return "-".to_string();
    };
    let seconds = seconds.max(0.0);
    if seconds < 60.0 {
        return "now".to_string();
    }
    let minutes = seconds / 60.0;
    if minutes < 60.0 {
        return format!("{}m", minutes as i64);
    }
    let hours = minutes / 60.0;
    if hours < 24.0 {
        return format!("{}h", hours as i64);
    }
    let days = hours / 24.0;
    if days < 14.0 {
        return format!("{}d", days as i64);
    }
    format!("{}w", (days / 7.0) as i64)
}

pub fn fmt_epoch(ts: Option<f64>) -> String {
    let Some(ts) = ts else {
        return "-".to_string();
    };
    if ts <= 0.0 {
        return "-".to_string();
    }
    match Local.timestamp_opt(ts as i64, 0) {
        chrono::LocalResult::Single(instant) => instant.format("%Y-%m-%d %H:%M").to_string(),
        _ => "-".to_string(),
    }
}

pub fn fmt_clock(ts: i64) -> String {
    Local
        .timestamp_opt(ts, 0)
        .single()
        .map(|instant| instant.format("%H:%M:%S").to_string())
        .unwrap_or_else(|| "--:--:--".to_string())
}

/// Seconds elapsed since local midnight, used by the Today view.
pub fn seconds_since_local_midnight() -> f64 {
    let now = Local::now();
    f64::from(now.num_seconds_from_midnight())
        + f64::from(now.timestamp_subsec_nanos()) / 1_000_000_000.0
}

/// Render a cadence that may be a label, seconds, or `{seconds,label}`.
pub fn cadence_text(value: Option<&Value>) -> String {
    match value {
        Some(Value::Object(object)) => {
            if let Some(label) = object.get("label").and_then(Value::as_str) {
                if !label.is_empty() {
                    return label.to_string();
                }
            }
            if let Some(label) = object.get("cadence_label").and_then(Value::as_str) {
                if !label.is_empty() {
                    return label.to_string();
                }
            }
            match as_f64(object.get("seconds")) {
                Some(seconds) if seconds <= 0.0 => "activity".to_string(),
                Some(seconds) => fmt_duration(Some(seconds)),
                None => "-".to_string(),
            }
        }
        Some(Value::Number(number)) => match number.as_f64() {
            Some(seconds) if seconds <= 0.0 => "activity".to_string(),
            Some(seconds) => fmt_duration(Some(seconds)),
            None => "-".to_string(),
        },
        Some(Value::String(text)) if !text.is_empty() => text.clone(),
        _ => "-".to_string(),
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct ThreadView {
    pub key: String,
    pub summary: String,
    pub headline: String,
    pub topic: String,
    pub status: String,
    pub kind: String,
    pub link: String,
    pub channel_name: String,
    pub root_author: String,
    pub priority: i64,
    pub priority_label: String,
    pub urgency: Option<f64>,
    pub relevance: Option<f64>,
    pub importance: bool,
    pub waiting: bool,
    pub done: bool,
    pub followed: bool,
    pub snoozed: bool,
    pub note: String,
    pub cadence: String,
    pub age_seconds: Option<f64>,
    pub age: String,
    pub closed_reason: String,
    pub closed_at: Option<f64>,
}

impl ThreadView {
    pub fn from_json(thread: &Value) -> Self {
        let item = merge_item(thread);
        let key = {
            let direct = as_text(item.get("key"));
            if direct.is_empty() {
                as_text(thread.get("key"))
            } else {
                direct
            }
        };
        let summary = one_line(&first_text(
            &item,
            &["summary", "title", "subject", "root_text"],
        ));
        let summary = if summary.is_empty() {
            key.clone()
        } else {
            summary
        };

        let reminder = item.get("reminder").filter(|value| value.is_object());
        let cadence_value = [
            item.get("cadence_label"),
            reminder.and_then(|value| value.get("cadence_label")),
            item.get("cadence"),
            reminder.and_then(|value| value.get("interval")),
        ]
        .into_iter()
        .flatten()
        .find(|value| !value.is_null())
        .cloned();
        let cadence = cadence_text(cadence_value.as_ref());

        let idle = as_f64(item.get("idle_seconds"));
        let last_activity = [
            item.get("last_activity"),
            item.get("last_activity_ts"),
            item.get("latest_ts"),
            item.get("updated"),
            item.get("last_active"),
        ]
        .into_iter()
        .flatten()
        .find_map(|value| as_f64(Some(value)));
        let age_seconds = match (idle, last_activity) {
            (Some(idle), _) => Some(idle.max(0.0)),
            (None, Some(stamp)) => {
                let now = Local::now().timestamp() as f64;
                Some((now - stamp).max(0.0))
            }
            (None, None) => None,
        };

        let status = {
            let status = as_text(item.get("status"));
            if status.is_empty() {
                as_text(item.get("state"))
            } else {
                status
            }
        };
        let waiting_flag = item
            .get("waiting_on_you")
            .or_else(|| item.get("waiting"))
            .and_then(json_bool);
        let waiting = match waiting_flag {
            Some(flag) => flag,
            None => {
                let lowered = status.to_lowercase();
                matches!(
                    lowered.as_str(),
                    "waiting"
                        | "waiting on you"
                        | "needs reply"
                        | "needs_reply"
                        | "action required"
                )
            }
        };

        let raw_priority = item.get("priority");
        let (priority, priority_label) = match raw_priority {
            Some(Value::Number(number)) => {
                let value = number.as_i64().unwrap_or(0);
                (
                    value,
                    if value > 0 {
                        format!("P{value}")
                    } else {
                        "-".to_string()
                    },
                )
            }
            Some(Value::String(text)) if !text.is_empty() => (0, text.to_uppercase()),
            _ => (0, "-".to_string()),
        };

        let link = {
            let link = as_text(item.get("link"));
            if link.is_empty() {
                as_text(item.get("url"))
            } else {
                link
            }
        };
        let kind = {
            let kind = as_text(item.get("kind"));
            if kind.is_empty() {
                "slack".to_string()
            } else {
                kind
            }
        };
        let followed = item.get("followed").and_then(json_bool).unwrap_or(true);

        ThreadView {
            key,
            summary,
            headline: one_line(&as_text(item.get("headline"))),
            topic: as_text(item.get("topic")),
            status,
            kind,
            link,
            channel_name: as_text(item.get("channel_name")),
            root_author: as_text(item.get("root_author")),
            priority,
            priority_label,
            urgency: as_f64(item.get("urgency")),
            relevance: as_f64(item.get("relevance")),
            importance: item.get("important").and_then(json_bool).unwrap_or(false),
            waiting,
            done: item.get("done").and_then(json_bool).unwrap_or(false),
            followed,
            snoozed: item
                .get("snoozed")
                .or_else(|| item.get("snooze"))
                .map(|value| json_bool(value).unwrap_or_else(|| !value.is_null()))
                .unwrap_or(false),
            note: as_text(item.get("note")),
            cadence,
            age_seconds,
            age: fmt_duration(age_seconds),
            closed_reason: as_text(item.get("closed_reason")),
            closed_at: as_f64(item.get("closed_at")),
        }
    }

    pub fn display_title(&self) -> &str {
        if self.headline.is_empty() {
            &self.summary
        } else {
            &self.headline
        }
    }

    pub fn matches(&self, needle: &str) -> bool {
        let needle = needle.to_lowercase();
        if needle.is_empty() {
            return true;
        }
        let haystack = [
            self.summary.as_str(),
            self.headline.as_str(),
            self.topic.as_str(),
            self.key.as_str(),
            self.kind.as_str(),
            self.note.as_str(),
            self.channel_name.as_str(),
            self.link.as_str(),
        ]
        .join(" ")
        .to_lowercase();
        haystack.contains(&needle)
    }
}

fn first_text(item: &Value, keys: &[&str]) -> String {
    for key in keys {
        let value = as_text(item.get(*key));
        if !value.is_empty() {
            return value;
        }
    }
    String::new()
}

fn json_bool(value: &Value) -> Option<bool> {
    match value {
        Value::Bool(flag) => Some(*flag),
        Value::Number(number) => number.as_i64().map(|value| value != 0),
        Value::String(text) => match text.trim().to_lowercase().as_str() {
            "true" | "yes" | "1" => Some(true),
            "false" | "no" | "0" | "" => Some(false),
            _ => None,
        },
        Value::Null => None,
        _ => None,
    }
}

fn merge_item(thread: &Value) -> Value {
    let Some(Value::Object(item)) = thread.get("item") else {
        return thread.clone();
    };
    let mut merged = item.clone();
    if let Some(top) = thread.as_object() {
        for (key, value) in top {
            if key != "item" {
                merged.insert(key.clone(), value.clone());
            }
        }
    }
    Value::Object(merged)
}

pub fn sort_views(views: &mut [ThreadView]) {
    views.sort_by(|left, right| {
        right
            .waiting
            .cmp(&left.waiting)
            .then_with(|| {
                right
                    .urgency
                    .unwrap_or(0.0)
                    .total_cmp(&left.urgency.unwrap_or(0.0))
            })
            .then_with(|| right.priority.cmp(&left.priority))
            .then_with(|| {
                left.age_seconds
                    .unwrap_or(f64::MAX)
                    .total_cmp(&right.age_seconds.unwrap_or(f64::MAX))
            })
    });
}

pub fn visible_views(threads: &[Value], search: &str) -> Vec<ThreadView> {
    let mut views: Vec<ThreadView> = threads.iter().map(ThreadView::from_json).collect();
    if !search.trim().is_empty() {
        views.retain(|view| view.matches(search.trim()));
    }
    sort_views(&mut views);
    views
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EntryKind {
    Thread,
    Group,
}

#[derive(Debug, Clone)]
pub struct Entry {
    pub key: String,
    pub kind: EntryKind,
    pub view: ThreadView,
    pub count: usize,
    pub topic: String,
    pub expanded: bool,
    pub indent: bool,
}

impl Entry {
    pub fn is_group(&self) -> bool {
        self.kind == EntryKind::Group
    }

    /// The thread key actions should target (groups act on their most urgent member).
    pub fn thread_key(&self) -> &str {
        &self.view.key
    }
}

/// Rows to render: plain threads plus collapsed topic groups.
pub fn build_entries(
    views: &[ThreadView],
    grouping: bool,
    expanded: &HashSet<String>,
) -> Vec<Entry> {
    if !grouping {
        return views
            .iter()
            .map(|view| Entry {
                key: view.key.clone(),
                kind: EntryKind::Thread,
                view: view.clone(),
                count: 1,
                topic: String::new(),
                expanded: false,
                indent: false,
            })
            .collect();
    }

    let mut order: Vec<(bool, String, Vec<ThreadView>)> = Vec::new();
    let mut groups: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
    for view in views {
        let topic = view.topic.trim().to_string();
        if topic.is_empty() {
            order.push((false, view.key.clone(), vec![view.clone()]));
            continue;
        }
        if let Some(index) = groups.get(&topic).copied() {
            order[index].2.push(view.clone());
        } else {
            groups.insert(topic.clone(), order.len());
            order.push((true, topic, vec![view.clone()]));
        }
    }

    let mut entries = Vec::new();
    for (grouped, key, mut members) in order {
        if !grouped || members.len() < 2 {
            let view = members.remove(0);
            entries.push(Entry {
                key: view.key.clone(),
                kind: EntryKind::Thread,
                view,
                count: 1,
                topic: String::new(),
                expanded: false,
                indent: false,
            });
            continue;
        }
        members.sort_by(|left, right| {
            right
                .urgency
                .unwrap_or(0.0)
                .total_cmp(&left.urgency.unwrap_or(0.0))
                .then_with(|| {
                    left.age_seconds
                        .unwrap_or(f64::MAX)
                        .total_cmp(&right.age_seconds.unwrap_or(f64::MAX))
                })
        });
        let is_expanded = expanded.contains(&key);
        let first = members[0].clone();
        entries.push(Entry {
            key: format!("topic:{key}"),
            kind: EntryKind::Group,
            view: first,
            count: members.len(),
            topic: key.clone(),
            expanded: is_expanded,
            indent: false,
        });
        if is_expanded {
            for view in members {
                entries.push(Entry {
                    key: view.key.clone(),
                    kind: EntryKind::Thread,
                    view,
                    count: 1,
                    topic: key.clone(),
                    expanded: false,
                    indent: true,
                });
            }
        }
    }
    entries
}

#[derive(Debug, Clone, Default)]
pub struct JobStep {
    pub label: String,
    pub detail: String,
    pub status: String,
    pub ts: Option<f64>,
}

impl JobStep {
    pub fn line(&self) -> String {
        match (self.label.is_empty(), self.detail.is_empty()) {
            (false, false) => format!("{} — {}", self.label, self.detail),
            (false, true) => self.label.clone(),
            (true, false) => self.detail.clone(),
            (true, true) => "(step)".to_string(),
        }
    }
}

pub fn job_steps(job: &Value) -> Vec<JobStep> {
    let Some(steps) = job.get("steps").and_then(Value::as_array) else {
        return Vec::new();
    };
    steps
        .iter()
        .filter(|step| step.is_object())
        .map(|step| JobStep {
            label: one_line(&as_text(step.get("label").or_else(|| step.get("message")))),
            detail: one_line(&as_text(step.get("detail"))),
            status: as_text(step.get("status")),
            ts: as_f64(step.get("ts")),
        })
        .collect()
}

pub fn job_status(job: &Value) -> String {
    let status = as_text(job.get("status")).to_lowercase();
    if status.is_empty() {
        "unknown".to_string()
    } else {
        status
    }
}

pub fn job_finished(job: &Value) -> bool {
    matches!(
        job_status(job).as_str(),
        "done"
            | "ok"
            | "finished"
            | "complete"
            | "completed"
            | "error"
            | "failed"
            | "cancelled"
            | "canceled"
    ) || job.get("finished").and_then(json_bool).unwrap_or(false)
}

pub fn job_succeeded(job: &Value) -> bool {
    matches!(
        job_status(job).as_str(),
        "done" | "ok" | "finished" | "complete" | "completed"
    )
}

pub fn job_title(job: &Value) -> String {
    one_line(&first_text(job, &["title", "question", "label"])).if_empty("job")
}

pub fn job_id(job: &Value) -> String {
    for key in ["id", "job_id", "job"] {
        let value = as_text(job.get(key));
        if !value.is_empty() {
            return value;
        }
    }
    String::new()
}

pub fn job_result(job: &Value) -> String {
    value_text(job.get("result"))
}

pub fn job_error(job: &Value) -> String {
    value_text(job.get("error"))
}

pub fn value_text(value: Option<&Value>) -> String {
    match value {
        Some(Value::String(text)) => text.clone(),
        Some(Value::Null) | None => String::new(),
        Some(other) => serde_json::to_string_pretty(other).unwrap_or_default(),
    }
}

trait IfEmpty {
    fn if_empty(self, fallback: &str) -> String;
}

impl IfEmpty for String {
    fn if_empty(self, fallback: &str) -> String {
        if self.trim().is_empty() {
            fallback.to_string()
        } else {
            self
        }
    }
}

/// `1d`/`6h`/`30m`/`90s`/`2w` -> seconds; `off` -> 0; `default` -> None.
pub fn parse_duration(value: &str) -> Result<Option<u64>, String> {
    let text = value.trim().to_lowercase();
    match text.as_str() {
        "off" | "never" | "none" => return Ok(Some(0)),
        "default" | "auto" => return Ok(None),
        _ => {}
    }
    let mut digits = String::new();
    let mut unit = None;
    for character in text.chars() {
        if character.is_ascii_digit() {
            if unit.is_some() {
                return Err(format!("not a duration: {value:?} (try 1d, 6h, off)"));
            }
            digits.push(character);
        } else if character.is_whitespace() {
            continue;
        } else {
            if unit.is_some() || digits.is_empty() {
                return Err(format!("not a duration: {value:?} (try 1d, 6h, off)"));
            }
            unit = Some(character);
        }
    }
    if digits.is_empty() {
        return Err(format!("not a duration: {value:?} (try 1d, 6h, off)"));
    }
    let amount: u64 = digits
        .parse()
        .map_err(|_| format!("not a duration: {value:?} (try 1d, 6h, off)"))?;
    let factor = match unit {
        None => 1,
        Some('s') => 1,
        Some('m') => 60,
        Some('h') => 3_600,
        Some('d') => 86_400,
        Some('w') => 604_800,
        Some(_) => return Err(format!("not a duration: {value:?} (try 1d, 6h, off)")),
    };
    Ok(Some(amount.saturating_mul(factor)))
}

pub fn duration_label(value: &str) -> Result<String, String> {
    match parse_duration(value)? {
        None => Ok("default".to_string()),
        Some(0) => Ok("off".to_string()),
        Some(seconds) => Ok(fmt_duration(Some(seconds as f64))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn view(value: Value) -> ThreadView {
        ThreadView::from_json(&value)
    }

    #[test]
    fn normalises_a_thread_payload() {
        let thread = view(json!({
            "key": "C1:1.0",
            "summary": "  dLocal   SAML login failure ",
            "headline": "dLocal SAML",
            "topic": "dlocal",
            "priority": 2,
            "urgency": 92,
            "relevance": 88,
            "important": true,
            "waiting_on_you": true,
            "idle_seconds": 3600,
            "cadence_label": "1d",
            "kind": "pr",
            "link": "https://example.test/x",
            "channel_name": "aaa-internal",
        }));
        assert_eq!(thread.summary, "dLocal SAML login failure");
        assert_eq!(thread.priority_label, "P2");
        assert_eq!(thread.urgency, Some(92.0));
        assert_eq!(thread.age, "1h");
        assert!(thread.waiting && thread.importance && !thread.done);
        assert_eq!(thread.display_title(), "dLocal SAML");
    }

    #[test]
    fn item_wrapper_is_merged_and_top_level_wins() {
        let thread = view(json!({
            "key": "C1:2.0",
            "item": {
                "key": "inner",
                "summary": "from item",
                "status": "open",
                "cadence": {"seconds": 21600}
            }
        }));
        assert_eq!(thread.key, "C1:2.0");
        assert_eq!(thread.summary, "from item");
        assert_eq!(thread.cadence, "6h");
    }

    #[test]
    fn waiting_can_come_from_status() {
        let thread = view(json!({"key": "x", "status": "needs reply"}));
        assert!(thread.waiting);
    }

    #[test]
    fn sorting_prefers_waiting_then_urgency() {
        let mut views = vec![
            view(json!({"key": "a", "urgency": 99})),
            view(json!({"key": "b", "urgency": 10, "waiting": true})),
            view(json!({"key": "c", "urgency": 50})),
        ];
        sort_views(&mut views);
        let keys: Vec<&str> = views.iter().map(|view| view.key.as_str()).collect();
        assert_eq!(keys, vec!["b", "a", "c"]);
    }

    #[test]
    fn groups_collapse_repeated_topics_and_expand() {
        let views = vec![
            view(json!({"key": "1", "topic": "dlocal", "urgency": 92})),
            view(json!({"key": "2", "topic": "dlocal", "urgency": 74})),
            view(json!({"key": "3", "topic": "calendar", "urgency": 20})),
        ];
        let collapsed = build_entries(&views, true, &HashSet::new());
        assert_eq!(collapsed.len(), 2);
        assert_eq!(collapsed[0].kind, EntryKind::Group);
        assert_eq!(collapsed[0].count, 2);
        assert_eq!(collapsed[0].view.key, "1");

        let mut expanded = HashSet::new();
        expanded.insert("dlocal".to_string());
        let open = build_entries(&views, true, &expanded);
        assert_eq!(open.len(), 4);
        assert!(open[1].indent);
    }

    #[test]
    fn search_matches_the_usual_fields() {
        let thread = view(json!({
            "key": "C1:9.0",
            "summary": "auditor-v2 backfill review",
            "channel_name": "aaa-internal"
        }));
        assert!(thread.matches("auditor"));
        assert!(thread.matches("AAA-INTERNAL"));
        assert!(!thread.matches("dlocal"));
    }

    #[test]
    fn parses_and_renders_durations() {
        assert_eq!(parse_duration("1d").unwrap(), Some(86_400));
        assert_eq!(parse_duration("off").unwrap(), Some(0));
        assert_eq!(parse_duration("default").unwrap(), None);
        assert!(parse_duration("soon").is_err());
        assert_eq!(duration_label("6h").unwrap(), "6h");
        assert_eq!(duration_label("off").unwrap(), "off");
    }
}
