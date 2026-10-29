//! Local conversation threads.
//!
//! The Hermes API answers one question at a time. A conversation is kept
//! client-side: every follow-up sends the transcript so far as the `conversation`
//! field, which the agent already treats as untrusted context. That gives the
//! TUI real, persisted threads without inventing server state.
//!
//! Conversations are stored under `$XDG_STATE_HOME/hermes/conversations.json`.

use crate::config;
use crate::model::one_line;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

pub const MAX_MESSAGES_PER_CONVERSATION: usize = 300;
pub const MAX_CONVERSATIONS: usize = 100;
const TRANSCRIPT_CAP: usize = 12_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    User,
    Assistant,
    Step,
    Error,
}

impl Role {
    pub fn label(self) -> &'static str {
        match self {
            Role::User => "you",
            Role::Assistant => "hermes",
            Role::Step => "step",
            Role::Error => "error",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub role: Role,
    pub text: String,
    #[serde(default)]
    pub ts: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub job_id: Option<String>,
}

impl Message {
    pub fn new(role: Role, text: impl Into<String>) -> Self {
        Self {
            role,
            text: text.into(),
            ts: now(),
            job_id: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation {
    pub id: String,
    pub title: String,
    pub created_at: i64,
    pub updated_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thread_key: Option<String>,
    #[serde(default)]
    pub messages: Vec<Message>,
    /// Set while a `POST /api/ask` job is still running so a restart can resume.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pending_job: Option<String>,
}

impl Conversation {
    pub fn draft(thread_key: Option<String>, title: Option<String>) -> Self {
        let timestamp = now();
        Self {
            id: format!("{timestamp}-{:x}", std::process::id()),
            title: title.unwrap_or_else(|| "New thread".to_string()),
            created_at: timestamp,
            updated_at: timestamp,
            thread_key,
            messages: Vec::new(),
            pending_job: None,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.messages.is_empty()
    }

    pub fn is_pending(&self) -> bool {
        self.pending_job.is_some()
    }

    pub fn title_or_placeholder(&self) -> &str {
        let title = self.title.trim();
        if title.is_empty() {
            "New thread"
        } else {
            title
        }
    }

    pub fn push(&mut self, message: Message) {
        self.messages.push(message);
        if self.messages.len() > MAX_MESSAGES_PER_CONVERSATION {
            let drop = self.messages.len() - MAX_MESSAGES_PER_CONVERSATION;
            self.messages.drain(0..drop);
        }
        self.updated_at = now();
    }

    pub fn push_user(&mut self, text: impl Into<String>) -> bool {
        let text = text.into();
        if self.title == "New thread" || self.title.trim().is_empty() {
            self.title = derive_title(&text);
        }
        self.push(Message::new(Role::User, text));
        true
    }

    pub fn push_assistant(&mut self, text: impl Into<String>) {
        self.push(Message::new(Role::Assistant, text));
        self.pending_job = None;
    }

    pub fn push_step(&mut self, text: impl Into<String>) {
        self.push(Message::new(Role::Step, text));
    }

    pub fn push_error(&mut self, text: impl Into<String>) {
        self.push(Message::new(Role::Error, text));
        self.pending_job = None;
    }

    /// User/assistant transcript for the `conversation` field, newest last.
    pub fn transcript(&self) -> String {
        let mut blocks: Vec<String> = self
            .messages
            .iter()
            .filter(|message| matches!(message.role, Role::User | Role::Assistant))
            .map(|message| format!("{}: {}", message.role.label(), message.text.trim()))
            .collect();
        let mut total = 0usize;
        let mut kept: Vec<String> = Vec::new();
        for block in blocks.drain(..).rev() {
            let length = block.chars().count() + 1;
            if total + length > TRANSCRIPT_CAP && !kept.is_empty() {
                break;
            }
            total += length;
            kept.push(block);
        }
        kept.reverse();
        kept.join("\n")
    }

    pub fn message_count(&self) -> usize {
        self.messages
            .iter()
            .filter(|message| matches!(message.role, Role::User | Role::Assistant))
            .count()
    }
}

pub fn derive_title(text: &str) -> String {
    let flat = one_line(text);
    if flat.is_empty() {
        return "New thread".to_string();
    }
    let limit = 58;
    if flat.chars().count() <= limit {
        return flat;
    }
    let mut title: String = flat.chars().take(limit - 1).collect();
    if let Some(index) = title.rfind(' ') {
        if index > 20 {
            title.truncate(index);
        }
    }
    title.push('…');
    title
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ChatStore {
    #[serde(default)]
    pub conversations: Vec<Conversation>,
    #[serde(skip)]
    pub path: PathBuf,
}

impl ChatStore {
    pub fn default_path() -> PathBuf {
        config::state_dir().join("conversations.json")
    }

    pub fn load() -> Self {
        Self::load_from(Self::default_path())
    }

    pub fn load_from(path: PathBuf) -> Self {
        let mut store = match fs::read_to_string(&path) {
            Ok(text) => serde_json::from_str::<ChatStore>(&text).unwrap_or_default(),
            Err(_) => ChatStore::default(),
        };
        store.path = path;
        store.sort();
        store
    }

    pub fn save(&self) {
        let _ = self.save_to(&self.path);
    }

    pub fn save_to(&self, path: &Path) -> std::io::Result<()> {
        if path.as_os_str().is_empty() {
            return Ok(());
        }
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let temporary = path.with_extension("json.tmp");
        let text = serde_json::to_string_pretty(self).map_err(std::io::Error::other)?;
        fs::write(&temporary, text)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&temporary, fs::Permissions::from_mode(0o600));
        }
        fs::rename(&temporary, path)?;
        Ok(())
    }

    pub fn sort(&mut self) {
        self.conversations
            .sort_by_key(|conversation| std::cmp::Reverse(conversation.updated_at));
        self.conversations.truncate(MAX_CONVERSATIONS);
    }

    pub fn insert(&mut self, conversation: Conversation) {
        if let Some(existing) = self
            .conversations
            .iter_mut()
            .find(|existing| existing.id == conversation.id)
        {
            *existing = conversation;
        } else {
            self.conversations.push(conversation);
        }
        self.sort();
    }

    pub fn get(&self, id: &str) -> Option<&Conversation> {
        self.conversations
            .iter()
            .find(|conversation| conversation.id == id)
    }

    pub fn get_mut(&mut self, id: &str) -> Option<&mut Conversation> {
        self.conversations
            .iter_mut()
            .find(|conversation| conversation.id == id)
    }

    pub fn remove(&mut self, id: &str) -> Option<Conversation> {
        let index = self
            .conversations
            .iter()
            .position(|conversation| conversation.id == id)?;
        Some(self.conversations.remove(index))
    }

    pub fn pending(&self) -> Vec<Conversation> {
        self.conversations
            .iter()
            .filter(|conversation| conversation.is_pending())
            .cloned()
            .collect()
    }
}

pub fn now() -> i64 {
    chrono::Local::now().timestamp()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derives_a_short_thread_title() {
        assert_eq!(
            derive_title("  Why   is the dLocal login failing? "),
            "Why is the dLocal login failing?"
        );
        let long = "a".repeat(100);
        let title = derive_title(&long);
        assert!(title.chars().count() <= 58);
        assert!(title.ends_with('…'));
    }

    #[test]
    fn transcript_keeps_only_the_conversation_and_caps_it() {
        let mut conversation = Conversation::draft(None, None);
        conversation.push_user("what is waiting on me?");
        conversation.push_step("reading state");
        conversation.push_assistant("Two threads need an answer.");
        let transcript = conversation.transcript();
        assert!(transcript.contains("you: what is waiting on me?"));
        assert!(transcript.contains("hermes: Two threads need an answer."));
        assert!(!transcript.contains("reading state"));
    }

    #[test]
    fn round_trips_through_disk() {
        let dir = std::env::temp_dir().join(format!("hermes-chat-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("conversations.json");
        let mut store = ChatStore::load_from(path.clone());
        let mut conversation = Conversation::draft(None, None);
        conversation.push_user("hello");
        conversation.push_assistant("hi");
        store.insert(conversation.clone());
        store.save();

        let reloaded = ChatStore::load_from(path.clone());
        assert_eq!(reloaded.conversations.len(), 1);
        assert_eq!(reloaded.conversations[0].title, "hello");
        assert_eq!(reloaded.conversations[0].messages.len(), 2);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn new_thread_placeholder_when_empty() {
        let conversation = Conversation::draft(None, None);
        assert!(conversation.is_empty());
        assert_eq!(conversation.title_or_placeholder(), "New thread");
    }
}
