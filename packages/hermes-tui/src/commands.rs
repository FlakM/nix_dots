//! Command surface shared by the command bar and the Threads actions.
//!
//! The words are the Slack control surface from PLATFORM.md, so muscle memory
//! carries over between Slack and `hermes-tui`. `run` is pure apart from the
//! API calls: it returns a [`CommandResult`], never touches the UI, and turns
//! every exception into a readable line.

use crate::api::{Api, ApiError};
use crate::model::{self, ThreadView};
use serde_json::{json, Value};

#[derive(Debug, Clone, Default)]
pub struct CommandResult {
    pub output: String,
    pub refresh: bool,
    pub job_id: Option<String>,
    pub search: Option<String>,
    pub help: bool,
    pub quit: bool,
    pub error: bool,
    /// Raw payload for callers that want to inspect it; the TUI does not.
    #[allow(dead_code)]
    pub data: Option<Value>,
}

impl CommandResult {
    pub fn ok(output: impl Into<String>) -> Self {
        Self {
            output: output.into(),
            ..Default::default()
        }
    }

    pub fn err(message: impl Into<String>) -> Self {
        Self {
            output: format!("error: {}", message.into()),
            error: true,
            ..Default::default()
        }
    }

    pub fn refresh(output: impl Into<String>) -> Self {
        Self {
            output: output.into(),
            refresh: true,
            ..Default::default()
        }
    }
}

/// `ask`, `investigate` and `draft` are routed through the Chat tab by the app.
pub fn ask_mode(word: &str) -> Option<&'static str> {
    match word.to_lowercase().as_str() {
        "ask" => Some("ask"),
        "investigate" => Some("investigate"),
        "draft" => Some("draft"),
        _ => None,
    }
}

pub fn run(api: &Api, line: &str, current_key: Option<&str>) -> CommandResult {
    let text = line.trim();
    if text.is_empty() {
        return CommandResult::default();
    }
    let (word, argument) = match text.split_once(char::is_whitespace) {
        Some((word, rest)) => (word.to_lowercase(), rest.trim().to_string()),
        None => (text.to_lowercase(), String::new()),
    };

    match word.as_str() {
        "help" | "?" => CommandResult {
            help: true,
            ..Default::default()
        },
        "quit" | "q" => CommandResult {
            quit: true,
            output: "bye".to_string(),
            ..Default::default()
        },
        "track" => track(api, &argument),
        "untrack" => untrack(api, &argument, current_key),
        "remind" => remind(api, &argument, current_key),
        "reminders" => reminders(api, &argument),
        "task" => task(api, &argument),
        "ask" | "investigate" | "draft" => legacy_ask(api, &word, &argument, current_key),
        "snooze" => snooze(api, &argument, current_key),
        "done" => done(api, current_key),
        "important" => important(api, current_key),
        "follow" => follow(api, current_key, true),
        "unfollow" => follow(api, current_key, false),
        "search" => {
            if argument.is_empty() {
                CommandResult {
                    output: "filter cleared".to_string(),
                    search: Some(String::new()),
                    ..Default::default()
                }
            } else {
                CommandResult {
                    output: format!("filtering by {:?}", argument),
                    search: Some(argument),
                    ..Default::default()
                }
            }
        }
        "history" => history(api, &argument),
        "notify" => notify(api, &argument),
        "remote" => remote(api, &argument),
        "status" => status(api),
        other => CommandResult::err(format!("unknown command {other:?} — press ? for help")),
    }
}

fn track(api: &Api, argument: &str) -> CommandResult {
    let (spec, cadence) = match parse_track_command(argument) {
        Ok(value) => value,
        Err(error) => return CommandResult::err(error),
    };
    let mut payload = match parse_track_spec(&spec) {
        Ok(value) => value,
        Err(error) => return CommandResult::err(error),
    };
    if let Some(cadence) = cadence.clone() {
        payload["cadence"] = Value::String(cadence);
    }
    match api.create_thread(&payload) {
        Ok(created) => {
            let view = ThreadView::from_json(&created);
            let key = if view.key.is_empty() {
                model::as_text(created.get("key"))
            } else {
                view.key.clone()
            };
            let key = if key.is_empty() { spec } else { key };
            let mut output = format!("tracked {key}");
            if let Some(cadence) = cadence {
                output.push_str(&format!(" every {cadence}"));
            }
            CommandResult {
                output,
                refresh: true,
                data: Some(created),
                ..Default::default()
            }
        }
        Err(error) => CommandResult::err(error.to_string()),
    }
}

fn untrack(api: &Api, argument: &str, current_key: Option<&str>) -> CommandResult {
    let key = match thread_argument(argument, current_key) {
        Ok(key) => key,
        Err(error) => return CommandResult::err(error),
    };
    match api.delete_thread(&key) {
        Ok(()) => CommandResult::refresh(format!("untracked {key}")),
        Err(error) => CommandResult::err(error.to_string()),
    }
}

fn remind(api: &Api, argument: &str, current_key: Option<&str>) -> CommandResult {
    let key = match required_thread(current_key) {
        Ok(key) => key,
        Err(error) => return CommandResult::err(error),
    };
    if argument.is_empty() {
        return match api.thread(&key) {
            Ok(thread) => {
                let view = ThreadView::from_json(&thread);
                CommandResult::ok(format!(
                    "reminders for {key}: every {} (default {})",
                    view.cadence,
                    default_cadence(api)
                ))
            }
            Err(error) => CommandResult::err(error.to_string()),
        };
    }
    let label = match model::duration_label(argument) {
        Ok(label) => label,
        Err(error) => return CommandResult::err(error),
    };
    match api.patch_thread(&key, &json!({ "cadence": label })) {
        Ok(_) => CommandResult::refresh(format!("{key}: reminders every {label}")),
        Err(error) => CommandResult::err(error.to_string()),
    }
}

fn reminders(api: &Api, argument: &str) -> CommandResult {
    if argument.is_empty() {
        return CommandResult::ok(format!(
            "default reminder cadence: {}",
            default_cadence(api)
        ));
    }
    let label = match model::duration_label(argument) {
        Ok(label) => label,
        Err(error) => return CommandResult::err(error),
    };
    match api.set_global_cadence(&label) {
        Ok(_) => CommandResult::refresh(format!("default reminder cadence set to {label}")),
        Err(ApiError::Server { status, .. }) if status == 404 || status == 405 => {
            CommandResult::err(
                "the server does not expose a global cadence endpoint yet; \
                 use `remind <value>` per thread",
            )
        }
        Err(error) => CommandResult::err(error.to_string()),
    }
}

fn task(api: &Api, argument: &str) -> CommandResult {
    if argument.is_empty() {
        return CommandResult::err("usage: task <natural language>");
    }
    match api.create_task(argument) {
        Ok(created) => {
            let title = {
                let value = model::as_text(created.get("title"));
                if value.is_empty() {
                    model::as_text(created.get("summary"))
                } else {
                    value
                }
            };
            let title = if title.is_empty() {
                argument.to_string()
            } else {
                title
            };
            let url = {
                let value = model::as_text(created.get("url"));
                if value.is_empty() {
                    model::as_text(created.get("link"))
                } else {
                    value
                }
            };
            let mut output = format!("task created: {title}");
            if !url.is_empty() {
                output.push_str(&format!(" — {url}"));
            }
            CommandResult {
                output,
                data: Some(created),
                ..Default::default()
            }
        }
        Err(error) => CommandResult::err(error.to_string()),
    }
}

fn legacy_ask(api: &Api, word: &str, argument: &str, current_key: Option<&str>) -> CommandResult {
    if word == "ask" && argument.is_empty() {
        return CommandResult::err("usage: ask <question>");
    }
    if word != "ask" && current_key.is_none() {
        return CommandResult::err(format!("{word} needs a selected thread"));
    }
    match api.ask(argument, current_key, "", word, "auto") {
        Ok(created) => {
            let job_id = api.job_id(&created);
            let note = if word == "ask" {
                String::new()
            } else {
                format!(" ({word})")
            };
            CommandResult {
                output: format!(
                    "job {} started{note} — steps stream in the Jobs tab",
                    job_id.clone().unwrap_or_else(|| "?".to_string())
                ),
                job_id,
                data: Some(created),
                ..Default::default()
            }
        }
        Err(error) => CommandResult::err(error.to_string()),
    }
}

fn snooze(api: &Api, argument: &str, current_key: Option<&str>) -> CommandResult {
    let key = match required_thread(current_key) {
        Ok(key) => key,
        Err(error) => return CommandResult::err(error),
    };
    if argument.is_empty() {
        return CommandResult::err("usage: snooze 2h | snooze off");
    }
    let seconds = match model::parse_duration(argument) {
        Ok(seconds) => seconds,
        Err(error) => return CommandResult::err(error),
    };
    let value = match seconds {
        None => Value::String("default".to_string()),
        Some(0) => json!(0),
        Some(_) => Value::String(argument.to_string()),
    };
    match api.patch_thread(&key, &json!({ "snooze": value })) {
        Ok(_) => CommandResult::refresh(format!("{key}: snoozed {argument}")),
        Err(error) => CommandResult::err(error.to_string()),
    }
}

fn done(api: &Api, current_key: Option<&str>) -> CommandResult {
    let key = match required_thread(current_key) {
        Ok(key) => key,
        Err(error) => return CommandResult::err(error),
    };
    match api.patch_thread(&key, &json!({ "done": true })) {
        Ok(_) => CommandResult::refresh(format!("{key}: marked done")),
        Err(error) => CommandResult::err(error.to_string()),
    }
}

fn important(api: &Api, current_key: Option<&str>) -> CommandResult {
    let key = match required_thread(current_key) {
        Ok(key) => key,
        Err(error) => return CommandResult::err(error),
    };
    let important = match api.thread(&key) {
        Ok(thread) => !ThreadView::from_json(&thread).importance,
        Err(error) => return CommandResult::err(error.to_string()),
    };
    match api.patch_thread(&key, &json!({ "important": important })) {
        Ok(_) => CommandResult::refresh(format!(
            "{key}: {}",
            if important {
                "important"
            } else {
                "not important"
            }
        )),
        Err(error) => CommandResult::err(error.to_string()),
    }
}

fn follow(api: &Api, current_key: Option<&str>, followed: bool) -> CommandResult {
    let key = match required_thread(current_key) {
        Ok(key) => key,
        Err(error) => return CommandResult::err(error),
    };
    match api.patch_thread(&key, &json!({ "followed": followed })) {
        Ok(_) => CommandResult::refresh(format!(
            "{key}: {}",
            if followed {
                "following"
            } else {
                "not following"
            }
        )),
        Err(error) => CommandResult::err(error.to_string()),
    }
}

fn history(api: &Api, argument: &str) -> CommandResult {
    let limit = if argument.is_empty() {
        10
    } else {
        match argument.parse::<usize>() {
            Ok(value) => value.clamp(1, 100),
            Err(_) => return CommandResult::err("usage: history [count]"),
        }
    };
    match api.jobs() {
        Ok(jobs) => {
            if jobs.is_empty() {
                return CommandResult::ok("no recent jobs");
            }
            let lines: Vec<String> = jobs
                .iter()
                .take(limit)
                .map(|job| {
                    let id = {
                        let value = model::job_id(job);
                        if value.is_empty() {
                            "?".to_string()
                        } else {
                            value
                        }
                    };
                    format!(
                        "{id}  {:<9}  {}",
                        model::job_status(job),
                        model::truncate(&model::job_title(job), 90)
                    )
                })
                .collect();
            CommandResult {
                output: lines.join("\n"),
                data: Some(Value::Array(jobs)),
                ..Default::default()
            }
        }
        Err(error) => CommandResult::err(error.to_string()),
    }
}

fn notify(api: &Api, argument: &str) -> CommandResult {
    if argument.is_empty() {
        return CommandResult::err("usage: notify <text>");
    }
    match api.notify(argument, "Hermes") {
        Ok(_) => CommandResult::ok("notification sent"),
        Err(error) => CommandResult::err(error.to_string()),
    }
}

fn remote(api: &Api, argument: &str) -> CommandResult {
    if argument.is_empty() {
        return CommandResult::err("usage: remote <command>");
    }
    match api.remote_run(argument) {
        Ok(created) => {
            let job_id = api.job_id(&created);
            let output = model::as_text(created.get("output"));
            if !output.is_empty() {
                return CommandResult {
                    output,
                    data: Some(created),
                    ..Default::default()
                };
            }
            CommandResult {
                output: format!(
                    "remote job {} started — steps stream in the Jobs tab",
                    job_id.clone().unwrap_or_else(|| "?".to_string())
                ),
                job_id,
                data: Some(created),
                ..Default::default()
            }
        }
        Err(error) => CommandResult::err(error.to_string()),
    }
}

fn status(api: &Api) -> CommandResult {
    let health = api.health().unwrap_or(Value::Null);
    let state = api.state().unwrap_or(Value::Null);
    let tracked = api.threads("tracked", 100).unwrap_or_default();
    let waiting = tracked
        .iter()
        .map(ThreadView::from_json)
        .filter(|view| view.waiting)
        .count();
    let snapshot = state.get("snapshot").cloned().unwrap_or(Value::Null);
    let counts = state.get("state").cloned().unwrap_or(Value::Null);
    let following = model::as_i64(snapshot.get("followed"));
    let version = {
        let value = model::as_text(health.get("version"));
        if value.is_empty() {
            "-".to_string()
        } else {
            value
        }
    };
    let age_text = match model::as_f64(health.get("state_age")) {
        Some(age) if age < 60.0 => "just now".to_string(),
        Some(age) => format!("{} old", model::fmt_duration(Some(age))),
        None => "-".to_string(),
    };
    let mut second = format!("{} tracked · {} waiting on you", tracked.len(), waiting);
    if let Some(following) = following {
        second.push_str(&format!(" · {following} followed"));
    }
    second.push_str(&format!(" · default cadence {}", default_cadence(api)));
    let mut lines = vec![format!(
        "hermes {version} · ok={} · state {age_text}",
        model::as_text(health.get("ok"))
    )];
    lines.push(second);
    let seen = model::as_i64(counts.get("subscriptions"));
    let history = model::as_i64(counts.get("threads"));
    if seen.is_some() || history.is_some() {
        lines.push(format!(
            "{} subscriptions · {} threads seen",
            seen.unwrap_or(0),
            history.unwrap_or(0)
        ));
    }
    CommandResult {
        output: lines.join("\n"),
        data: Some(json!({ "health": health, "state": state })),
        ..Default::default()
    }
}

fn default_cadence(api: &Api) -> String {
    let Ok(state) = api.state() else {
        return "-".to_string();
    };
    for key in ["cadence", "default_cadence", "cadence_defaults"] {
        if let Some(value) = state.get(key) {
            if !value.is_null() {
                return model::cadence_text(Some(value));
            }
        }
    }
    if let Some(seconds) = state
        .get("features")
        .and_then(|features| features.get("tracking"))
        .and_then(|tracking| tracking.get("default_reminder_seconds"))
        .and_then(Value::as_f64)
    {
        return model::fmt_duration(Some(seconds));
    }
    "-".to_string()
}

fn required_thread(current_key: Option<&str>) -> Result<String, String> {
    current_key
        .filter(|key| !key.is_empty())
        .map(str::to_string)
        .ok_or_else(|| "no thread selected — pick one in the Threads tab first".to_string())
}

fn thread_argument(argument: &str, current_key: Option<&str>) -> Result<String, String> {
    if argument.is_empty() {
        required_thread(current_key)
    } else {
        Ok(argument.to_string())
    }
}

pub fn slack_ts_from_permalink(digits: &str) -> String {
    if digits.contains('.') {
        return digits.to_string();
    }
    if digits.len() <= 10 {
        return digits.to_string();
    }
    format!("{}.{}", &digits[..10], &digits[10..])
}

/// `<spec> [every 1d]` -> (spec, cadence label or None).
pub fn parse_track_command(text: &str) -> Result<(String, Option<String>), String> {
    let parts: Vec<&str> = text.split_whitespace().collect();
    if parts.is_empty() {
        return Err("track needs a Slack/Jira/PR URL or <channel>:<thread_ts>".to_string());
    }
    let mut cadence = None;
    let mut spec_parts = parts.clone();
    if let Some(index) = parts.iter().position(|part| *part == "every") {
        if index + 1 >= parts.len() {
            return Err("`every` needs a duration, e.g. `track <url> every 6h`".to_string());
        }
        cadence = Some(model::duration_label(parts[index + 1])?);
        spec_parts = parts[..index].to_vec();
    }
    let spec = spec_parts.join(" ");
    if spec.is_empty() {
        return Err("track needs a Slack/Jira/PR URL or <channel>:<thread_ts>".to_string());
    }
    Ok((spec, cadence))
}

/// Turn a permalink, a thread key or a bare URL into a `POST /api/threads` body.
pub fn parse_track_spec(spec: &str) -> Result<Value, String> {
    let spec = spec.trim();
    if spec.is_empty() {
        return Err("track needs a Slack/Jira/PR URL or <channel>:<thread_ts>".to_string());
    }

    if let Some((channel, thread_ts)) = parse_slack_permalink(spec) {
        return Ok(json!({
            "kind": "slack",
            "url": spec,
            "channel": channel,
            "thread_ts": thread_ts,
        }));
    }

    if let Some((channel, thread_ts)) = parse_slack_key(spec) {
        return Ok(json!({
            "kind": "slack",
            "channel": channel,
            "thread_ts": thread_ts,
        }));
    }

    if is_jira_url(spec) {
        return Ok(json!({ "kind": "jira", "url": spec }));
    }

    if is_pull_request_url(spec) || spec.contains("github.com") || spec.contains("gitlab") {
        return Ok(json!({ "kind": "pr", "url": spec }));
    }

    if spec.starts_with("http://") || spec.starts_with("https://") {
        if spec.contains("/archives/") {
            return Ok(json!({ "kind": "slack", "url": spec }));
        }
        return Ok(json!({ "kind": "pr", "url": spec }));
    }

    Err(
        "unrecognised thread reference (expected a Slack/Jira/PR URL or \
         <channel>:<thread_ts>)"
            .to_string(),
    )
}

fn parse_slack_permalink(spec: &str) -> Option<(String, String)> {
    let rest = spec
        .strip_prefix("https://")
        .or_else(|| spec.strip_prefix("http://"))?;
    let (host, rest) = rest.split_once('/')?;
    if !host.ends_with(".slack.com") {
        return None;
    }
    let path = rest.split(['?', '#']).next().unwrap_or_default();
    let segments: Vec<&str> = path.trim_end_matches('/').split('/').collect();
    if segments.len() < 3 || segments[0] != "archives" {
        return None;
    }
    let channel = segments[1];
    let digits = segments[2].strip_prefix('p')?;
    if digits.len() < 10 || !digits.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    if !channel
        .bytes()
        .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit())
    {
        return None;
    }
    Some((channel.to_string(), slack_ts_from_permalink(digits)))
}

fn parse_slack_key(spec: &str) -> Option<(String, String)> {
    let (channel, timestamp) = spec.split_once(':')?;
    if channel.is_empty()
        || !channel
            .bytes()
            .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit())
    {
        return None;
    }
    let (seconds, fraction) = timestamp.split_once('.')?;
    if seconds.len() < 10
        || !seconds.bytes().all(|byte| byte.is_ascii_digit())
        || fraction.is_empty()
        || !fraction.bytes().all(|byte| byte.is_ascii_digit())
    {
        return None;
    }
    Some((channel.to_string(), timestamp.to_string()))
}

fn is_jira_url(spec: &str) -> bool {
    let Some(index) = spec.find("/browse/") else {
        return false;
    };
    let issue = spec[index + "/browse/".len()..]
        .split(['/', '?', '#'])
        .next()
        .unwrap_or_default();
    let Some((prefix, number)) = issue.rsplit_once('-') else {
        return false;
    };
    !prefix.is_empty()
        && prefix.as_bytes()[0].is_ascii_uppercase()
        && prefix
            .bytes()
            .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit() || byte == b'_')
        && !number.is_empty()
        && number.bytes().all(|byte| byte.is_ascii_digit())
}

fn is_pull_request_url(spec: &str) -> bool {
    for marker in ["/pull/", "/merge_requests/"] {
        if let Some(index) = spec.find(marker) {
            let number = spec[index + marker.len()..]
                .split(['/', '?', '#'])
                .next()
                .unwrap_or_default();
            if !number.is_empty() && number.bytes().all(|byte| byte.is_ascii_digit()) {
                return true;
            }
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_slack_permalinks_into_channel_and_ts() {
        let payload = parse_track_spec(
            "https://aaa.slack.com/archives/C0123ABCD/p1790929532923549?thread_ts=1.2",
        )
        .unwrap();
        assert_eq!(payload["kind"], "slack");
        assert_eq!(payload["channel"], "C0123ABCD");
        assert_eq!(payload["thread_ts"], "1790929532.923549");
        assert_eq!(
            payload["url"],
            "https://aaa.slack.com/archives/C0123ABCD/p1790929532923549?thread_ts=1.2"
        );
    }

    #[test]
    fn parses_slack_thread_keys() {
        let payload = parse_track_spec("C0123ABCD:1790929532.923549").unwrap();
        assert_eq!(payload["channel"], "C0123ABCD");
        assert_eq!(payload["thread_ts"], "1790929532.923549");
    }

    #[test]
    fn detects_jira_and_pull_requests() {
        assert_eq!(
            parse_track_spec("https://coralogix.atlassian.net/browse/CX-1234").unwrap()["kind"],
            "jira"
        );
        assert_eq!(
            parse_track_spec("https://github.com/FlakM/nix_dots/pull/42").unwrap()["kind"],
            "pr"
        );
        assert!(parse_track_spec("not a link").is_err());
    }

    #[test]
    fn track_command_supports_a_cadence() {
        let (spec, cadence) =
            parse_track_command("https://github.com/x/y/pull/1 every 6h").unwrap();
        assert!(spec.ends_with("/pull/1"));
        assert_eq!(cadence.as_deref(), Some("6h"));
        assert!(parse_track_command("some-url every").is_err());
        assert!(parse_track_command("").is_err());
    }
}
