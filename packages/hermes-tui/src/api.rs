//! Blocking client for the Hermes HTTP API (see PLATFORM.md).
//!
//! Every call goes to the agent on the odroid; nothing is invented locally.
//! Errors are normalised so the UI can print one readable line.

use crate::config::Config;
use crate::model;
use serde_json::{json, Value};
use std::fmt;
use std::time::Duration;
use ureq::{Agent, Body};

#[derive(Debug, Clone)]
pub enum ApiError {
    /// Network/DNS/timeout: "the API is down".
    Unreachable(String),
    /// The server answered with an error (message in the payload).
    Server { status: u16, message: String },
}

impl fmt::Display for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ApiError::Unreachable(message) => f.write_str(message),
            ApiError::Server { status, message } => {
                if *status == 401 || *status == 403 {
                    write!(f, "HTTP {status} (check the API token): {message}")
                } else {
                    write!(f, "HTTP {status}: {message}")
                }
            }
        }
    }
}

impl std::error::Error for ApiError {}

pub type ApiResult<T> = Result<T, ApiError>;

#[derive(Clone)]
pub struct Api {
    base: String,
    token: String,
    agent: Agent,
}

impl Api {
    pub fn new(config: &Config) -> Self {
        let agent: Agent = Agent::config_builder()
            .timeout_global(Some(Duration::from_secs(25)))
            .timeout_connect(Some(Duration::from_secs(10)))
            .http_status_as_error(false)
            .user_agent(concat!("hermes-tui/", env!("CARGO_PKG_VERSION")))
            .build()
            .into();
        Self {
            base: config.api_url.trim_end_matches('/').to_string(),
            token: config.token.clone(),
            agent,
        }
    }

    pub fn base(&self) -> &str {
        &self.base
    }

    pub fn token(&self) -> &str {
        &self.token
    }

    fn url(&self, path: &str, params: &[(&str, String)]) -> String {
        let mut url = format!("{}{}", self.base, path);
        if params.is_empty() {
            return url;
        }
        url.push('?');
        for (index, (key, value)) in params.iter().enumerate() {
            if index > 0 {
                url.push('&');
            }
            url.push_str(key);
            url.push('=');
            url.push_str(&query_encode(value));
        }
        url
    }

    fn call(
        &self,
        method: &str,
        url: &str,
        body: Option<&Value>,
    ) -> Result<ureq::http::Response<Body>, ApiError> {
        let auth = format!("Bearer {}", self.token);
        let result = match method {
            "GET" => self
                .agent
                .get(url)
                .header("Authorization", &auth)
                .header("Accept", "application/json")
                .call(),
            "DELETE" => self
                .agent
                .delete(url)
                .header("Authorization", &auth)
                .header("Accept", "application/json")
                .call(),
            "POST" | "PATCH" => {
                let builder = if method == "POST" {
                    self.agent.post(url)
                } else {
                    self.agent.patch(url)
                }
                .header("Authorization", &auth)
                .header("Accept", "application/json");
                match body {
                    Some(payload) => builder.send_json(payload),
                    None => builder.send_empty(),
                }
            }
            other => {
                return Err(ApiError::Unreachable(format!(
                    "unsupported HTTP method {other}"
                )))
            }
        };
        result.map_err(|error| match error {
            ureq::Error::Timeout(_) => {
                ApiError::Unreachable(format!("timed out talking to Hermes at {}", self.base))
            }
            ureq::Error::HostNotFound => {
                ApiError::Unreachable(format!("cannot resolve {} (offline?)", self.base))
            }
            other => {
                ApiError::Unreachable(format!("cannot reach Hermes at {}: {other}", self.base))
            }
        })
    }

    fn request(
        &self,
        method: &str,
        path: &str,
        params: &[(&str, String)],
        body: Option<&Value>,
    ) -> ApiResult<Option<Value>> {
        let url = self.url(path, params);
        let response = self.call(method, &url, body)?;
        let status = response.status().as_u16();
        let mut response_body = response.into_body();
        let text = response_body.read_to_string().unwrap_or_default();
        if !(200..300).contains(&status) {
            let message = error_message(&text, status);
            return Err(ApiError::Server { status, message });
        }
        let text = text.trim();
        if text.is_empty() {
            return Ok(None);
        }
        match serde_json::from_str::<Value>(text) {
            Ok(value) => Ok(Some(value)),
            Err(_) => Ok(Some(Value::String(text.to_string()))),
        }
    }

    // -- health / state ---------------------------------------------------

    pub fn health(&self) -> ApiResult<Value> {
        Ok(self
            .request("GET", "/api/health", &[], None)?
            .unwrap_or(Value::Null))
    }

    pub fn state(&self) -> ApiResult<Value> {
        Ok(self
            .request("GET", "/api/state", &[], None)?
            .unwrap_or(Value::Null))
    }

    // -- threads ----------------------------------------------------------

    pub fn threads(&self, filter: &str, limit: u32) -> ApiResult<Vec<Value>> {
        let data = self.request(
            "GET",
            "/api/threads",
            &[("filter", filter.to_string()), ("limit", limit.to_string())],
            None,
        )?;
        Ok(unwrap_list(data, &["threads", "items", "results", "data"]))
    }

    pub fn thread(&self, key: &str) -> ApiResult<Value> {
        Ok(self
            .request(
                "GET",
                &format!("/api/threads/{}", path_encode(key)),
                &[],
                None,
            )?
            .unwrap_or(Value::Null))
    }

    pub fn create_thread(&self, payload: &Value) -> ApiResult<Value> {
        Ok(self
            .request("POST", "/api/threads", &[], Some(payload))?
            .unwrap_or(Value::Null))
    }

    pub fn patch_thread(&self, key: &str, payload: &Value) -> ApiResult<Value> {
        Ok(self
            .request(
                "PATCH",
                &format!("/api/threads/{}", path_encode(key)),
                &[],
                Some(payload),
            )?
            .unwrap_or(Value::Null))
    }

    pub fn delete_thread(&self, key: &str) -> ApiResult<()> {
        self.request(
            "DELETE",
            &format!("/api/threads/{}", path_encode(key)),
            &[],
            None,
        )?;
        Ok(())
    }

    pub fn set_global_cadence(&self, label: &str) -> ApiResult<Value> {
        Ok(self
            .request(
                "POST",
                "/api/reminders",
                &[],
                Some(&json!({ "cadence": label })),
            )?
            .unwrap_or(Value::Null))
    }

    // -- tasks / ask -------------------------------------------------------

    pub fn create_task(&self, text: &str) -> ApiResult<Value> {
        Ok(self
            .request("POST", "/api/tasks", &[], Some(&json!({ "text": text })))?
            .unwrap_or(Value::Null))
    }

    pub fn ask(
        &self,
        question: &str,
        thread_key: Option<&str>,
        conversation: &str,
        mode: &str,
        speed: &str,
    ) -> ApiResult<Value> {
        let mut payload = json!({
            "question": question,
            "mode": mode,
            "speed": speed,
        });
        if let Some(key) = thread_key.filter(|key| !key.is_empty()) {
            payload["thread_key"] = Value::String(key.to_string());
        }
        if !conversation.is_empty() {
            payload["conversation"] = Value::String(conversation.to_string());
        }
        Ok(self
            .request("POST", "/api/ask", &[], Some(&payload))?
            .unwrap_or(Value::Null))
    }

    pub fn notify(&self, body: &str, title: &str) -> ApiResult<Value> {
        Ok(self
            .request(
                "POST",
                "/api/notify",
                &[],
                Some(&json!({ "title": title, "body": body })),
            )?
            .unwrap_or(Value::Null))
    }

    // -- jobs --------------------------------------------------------------

    pub fn jobs(&self) -> ApiResult<Vec<Value>> {
        let data = self.request("GET", "/api/jobs", &[], None)?;
        Ok(unwrap_list(data, &["jobs", "items", "data"]))
    }

    pub fn job(&self, id: &str) -> ApiResult<Value> {
        Ok(self
            .request("GET", &format!("/api/jobs/{}", path_encode(id)), &[], None)?
            .unwrap_or(Value::Null))
    }

    pub fn cancel_job(&self, id: &str) -> ApiResult<()> {
        self.request(
            "POST",
            &format!("/api/jobs/{}/cancel", path_encode(id)),
            &[],
            None,
        )?;
        Ok(())
    }

    pub fn remote_run(&self, command: &str) -> ApiResult<Value> {
        Ok(self
            .request(
                "POST",
                "/api/remote/run",
                &[],
                Some(&json!({ "command": command })),
            )?
            .unwrap_or(Value::Null))
    }

    pub fn job_id(&self, data: &Value) -> Option<String> {
        for key in ["job_id", "job", "id"] {
            let value = model::as_text(data.get(key));
            if !value.is_empty() {
                return Some(value);
            }
        }
        None
    }
}

fn unwrap_list(data: Option<Value>, keys: &[&str]) -> Vec<Value> {
    match data {
        Some(Value::Array(items)) => items.into_iter().filter(|item| item.is_object()).collect(),
        Some(Value::Object(mut object)) => {
            for key in keys {
                if let Some(Value::Array(items)) = object.remove(*key) {
                    return items.into_iter().filter(|item| item.is_object()).collect();
                }
            }
            Vec::new()
        }
        _ => Vec::new(),
    }
}

fn error_message(text: &str, status: u16) -> String {
    if let Ok(Value::Object(object)) = serde_json::from_str::<Value>(text) {
        for key in ["error", "message"] {
            let message = model::as_text(object.get(key));
            if !message.is_empty() {
                return message;
            }
        }
    }
    let trimmed = text.trim();
    if !trimmed.is_empty() {
        return model::truncate(trimmed, 400);
    }
    format!("request failed with HTTP {status}")
}

/// Percent-encode a path segment (thread keys contain `:` which is legal, but
/// `/` and spaces must not leak).
fn path_encode(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' | b':' | b'*' => {
                out.push(byte as char)
            }
            other => out.push_str(&format!("%{other:02X}")),
        }
    }
    out
}

/// Percent-encode a query value, leaving `:` readable for thread cursors.
fn query_encode(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' | b':' => {
                out.push(byte as char)
            }
            b' ' => out.push_str("%20"),
            other => out.push_str(&format!("%{other:02X}")),
        }
    }
    out
}

/// An agent for the long-lived SSE request: no global timeout, but a finite
/// connect / response-header timeout so an offline server fails fast.
pub fn stream_agent() -> Agent {
    Agent::config_builder()
        .timeout_connect(Some(Duration::from_secs(10)))
        .timeout_recv_response(Some(Duration::from_secs(90)))
        .http_status_as_error(false)
        .user_agent(concat!("hermes-tui/", env!("CARGO_PKG_VERSION")))
        .build()
        .into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encodes_path_segments_but_keeps_thread_keys_readable() {
        assert_eq!(path_encode("C1:1.0"), "C1:1.0");
        assert_eq!(path_encode("a/b c"), "a%2Fb%20c");
    }

    #[test]
    fn unwraps_the_threads_envelope() {
        let data = json!({"threads": [{"key": "a"}, "ignored"], "count": 1});
        let items = unwrap_list(Some(data), &["threads"]);
        assert_eq!(items.len(), 1);
        assert_eq!(model::as_text(items[0].get("key")), "a");
    }

    #[test]
    fn error_message_prefers_the_api_field() {
        assert_eq!(
            error_message(r#"{"error":"no such thread"}"#, 404),
            "no such thread"
        );
        assert_eq!(error_message("plain failure", 500), "plain failure");
    }
}
