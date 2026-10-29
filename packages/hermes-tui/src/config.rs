//! Client configuration.
//!
//! Reads `~/.config/hermes/client.env` (written by home-manager):
//!
//! ```text
//! HERMES_API_URL=https://hermes.house.flakm.com
//! HERMES_API_TOKEN_FILE=/run/user/1000/secrets/hermes_api_token
//! ```
//!
//! Environment variables win over the file so the TUI stays easy to point at
//! a development server. The token itself is always read from the file named
//! by `HERMES_API_TOKEN_FILE`; a literal `HERMES_API_TOKEN` is accepted for
//! tests and one-off runs.

use std::collections::BTreeMap;
use std::env;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

pub const DEFAULT_API_URL: &str = "https://hermes.house.flakm.com";

#[derive(Debug, Clone)]
pub struct Config {
    pub api_url: String,
    pub token: String,
    /// Kept for diagnostics; the token itself is never logged.
    #[allow(dead_code)]
    pub token_file: Option<PathBuf>,
    #[allow(dead_code)]
    pub env_file: Option<PathBuf>,
}

#[derive(Debug, Clone)]
pub struct ConfigError(pub String);

impl fmt::Display for ConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for ConfigError {}

fn home_dir() -> Option<PathBuf> {
    env::var_os("HOME").map(PathBuf::from)
}

fn xdg_dir(variable: &str, fallback: &str) -> PathBuf {
    if let Some(value) = env::var_os(variable) {
        if !value.is_empty() {
            return PathBuf::from(value);
        }
    }
    home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(fallback)
}

/// `~/.cache/hermes` (honours `XDG_CACHE_HOME`).
pub fn cache_dir() -> PathBuf {
    xdg_dir("XDG_CACHE_HOME", ".cache").join("hermes")
}

/// `~/.local/state/hermes` (honours `XDG_STATE_HOME`) — conversations live here.
pub fn state_dir() -> PathBuf {
    xdg_dir("XDG_STATE_HOME", ".local/state").join("hermes")
}

pub fn env_file_path() -> PathBuf {
    xdg_dir("XDG_CONFIG_HOME", ".config")
        .join("hermes")
        .join("client.env")
}

/// Tiny `KEY=VALUE` parser; comments and optional quotes/`export`.
pub fn parse_env(text: &str) -> BTreeMap<String, String> {
    let mut values = BTreeMap::new();
    for raw in text.lines() {
        let mut line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(rest) = line.strip_prefix("export ") {
            line = rest.trim_start();
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        let mut value = value.trim();
        if value.len() >= 2 {
            let first = value.as_bytes()[0] as char;
            let last = value.as_bytes()[value.len() - 1] as char;
            if first == last && (first == '"' || first == '\'') {
                value = &value[1..value.len() - 1];
            }
        }
        if !key.is_empty() {
            values.insert(key.to_string(), value.to_string());
        }
    }
    values
}

pub fn normalize_url(url: &str) -> Result<String, ConfigError> {
    let url = url.trim().trim_end_matches('/');
    if url.is_empty() {
        return Err(ConfigError("HERMES_API_URL is empty".into()));
    }
    if !(url.starts_with("http://") || url.starts_with("https://")) {
        return Err(ConfigError(format!(
            "HERMES_API_URL must start with http:// or https:// (got {url:?})"
        )));
    }
    // nginx exposes the API under /api/; the client adds that itself.
    Ok(url.strip_suffix("/api").unwrap_or(url).to_string())
}

pub fn load() -> Result<Config, ConfigError> {
    load_from(None)
}

pub fn load_from(path: Option<&Path>) -> Result<Config, ConfigError> {
    let env_path = path.map(Path::to_path_buf).unwrap_or_else(env_file_path);
    let file_values = if env_path.is_file() {
        match fs::read_to_string(&env_path) {
            Ok(text) => parse_env(&text),
            Err(exc) => {
                return Err(ConfigError(format!(
                    "cannot read {}: {exc}",
                    env_path.display()
                )))
            }
        }
    } else {
        BTreeMap::new()
    };

    let api_url = normalize_url(
        &env::var("HERMES_API_URL")
            .ok()
            .filter(|value| !value.trim().is_empty())
            .or_else(|| file_values.get("HERMES_API_URL").cloned())
            .unwrap_or_else(|| DEFAULT_API_URL.to_string()),
    )?;

    let mut token = env::var("HERMES_API_TOKEN")
        .unwrap_or_default()
        .trim()
        .to_string();
    let mut token_file = env::var("HERMES_API_TOKEN_FILE")
        .ok()
        .filter(|value| !value.is_empty())
        .or_else(|| file_values.get("HERMES_API_TOKEN_FILE").cloned())
        .map(PathBuf::from);

    if token.is_empty() {
        let Some(path) = token_file.clone() else {
            return Err(ConfigError(format!(
                "no Hermes API token configured (set HERMES_API_TOKEN_FILE in {})",
                env_path.display()
            )));
        };
        let expanded = expand_home(&path);
        match fs::read_to_string(&expanded) {
            Ok(contents) => token = contents.trim().to_string(),
            Err(exc) => {
                return Err(ConfigError(format!(
                    "cannot read Hermes API token {}: {}",
                    expanded.display(),
                    exc.kind()
                )))
            }
        }
        if token.is_empty() {
            return Err(ConfigError(format!(
                "Hermes API token file {} is empty",
                expanded.display()
            )));
        }
        token_file = Some(expanded);
    }

    Ok(Config {
        api_url,
        token,
        token_file,
        env_file: env_path.exists().then_some(env_path),
    })
}

fn expand_home(path: &Path) -> PathBuf {
    let text = path.to_string_lossy();
    if let Some(rest) = text.strip_prefix("~/") {
        if let Some(home) = home_dir() {
            return home.join(rest);
        }
    }
    path.to_path_buf()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or_default();
        std::env::temp_dir().join(format!(
            "hermes-config-test-{}-{tag}-{nanos}",
            std::process::id()
        ))
    }

    #[test]
    fn parses_comments_quotes_and_export() {
        let values = parse_env(
            "# comment\n\nHERMES_API_URL=https://example.test\n\
             export HERMES_API_TOKEN_FILE='/run/secrets/token'\n\
             ignored line\n",
        );
        assert_eq!(
            values.get("HERMES_API_URL").map(String::as_str),
            Some("https://example.test")
        );
        assert_eq!(
            values.get("HERMES_API_TOKEN_FILE").map(String::as_str),
            Some("/run/secrets/token")
        );
        assert_eq!(values.len(), 2);
    }

    #[test]
    fn normalizes_trailing_slashes_and_api_suffix() {
        assert_eq!(
            normalize_url("https://hermes.test/api/").unwrap(),
            "https://hermes.test"
        );
        assert!(normalize_url("hermes.test").is_err());
        assert!(normalize_url("").is_err());
    }

    #[test]
    fn loads_token_from_file() {
        let dir = temp_dir("token");
        fs::create_dir_all(&dir).unwrap();
        let token = dir.join("token");
        fs::write(&token, "  s3cret\n").unwrap();
        let env = dir.join("client.env");
        fs::write(
            &env,
            format!(
                "HERMES_API_URL=https://hermes.test\nHERMES_API_TOKEN_FILE={}\n",
                token.display()
            ),
        )
        .unwrap();

        // Clear the variables that would win over the file.
        std::env::remove_var("HERMES_API_URL");
        std::env::remove_var("HERMES_API_TOKEN");
        std::env::remove_var("HERMES_API_TOKEN_FILE");

        let config = load_from(Some(&env)).unwrap();
        assert_eq!(config.api_url, "https://hermes.test");
        assert_eq!(config.token, "s3cret");
        assert_eq!(config.token_file.as_deref(), Some(token.as_path()));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn missing_token_is_a_readable_error() {
        let dir = temp_dir("missing");
        fs::create_dir_all(&dir).unwrap();
        let env = dir.join("client.env");
        fs::write(&env, "HERMES_API_URL=https://hermes.test\n").unwrap();
        std::env::remove_var("HERMES_API_TOKEN");
        std::env::remove_var("HERMES_API_TOKEN_FILE");
        let error = load_from(Some(&env)).unwrap_err().to_string();
        assert!(error.contains("no Hermes API token configured"), "{error}");
        let _ = fs::remove_dir_all(&dir);
    }
}
