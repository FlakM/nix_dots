//! Application state and event loop.
//!
//! Three top-level tabs: **Chat** (client-side conversation threads), **Threads**
//! (tracked Slack/PR/Jira threads) and **Jobs** (agent jobs and the live event
//! feed). Everything network-facing runs on worker threads and reports back as
//! an [`AppEvent`], so the UI never blocks and an offline API only shows a
//! banner.

use crate::api::Api;
use crate::chat::{ChatStore, Conversation};
use crate::commands::{self, CommandResult};
use crate::config;
use crate::events;
use crate::model::{self, Entry, JobStep, ThreadView};
use crate::store;
use crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{Receiver, Sender};
use std::sync::Arc;
use std::time::{Duration, Instant};

pub const THREADS_REFRESH: Duration = Duration::from_secs(8);
pub const JOBS_REFRESH: Duration = Duration::from_secs(15);
const UNREAD_REFRESH: Duration = Duration::from_secs(5);
const TOAST_TTL: Duration = Duration::from_secs(6);
pub const PENDING_SENTINEL: &str = "pending";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tab {
    Chat,
    Today,
    Threads,
    Jobs,
}

impl Tab {
    pub const ALL: [Tab; 4] = [Tab::Chat, Tab::Today, Tab::Threads, Tab::Jobs];

    pub fn index(self) -> usize {
        match self {
            Tab::Chat => 0,
            Tab::Today => 1,
            Tab::Threads => 2,
            Tab::Jobs => 3,
        }
    }

    pub fn title(self) -> &'static str {
        match self {
            Tab::Chat => "Chat",
            Tab::Today => "Today",
            Tab::Threads => "Threads",
            Tab::Jobs => "Jobs",
        }
    }

    pub fn next(self) -> Self {
        Tab::ALL[(self.index() + 1) % Tab::ALL.len()]
    }

    pub fn previous(self) -> Self {
        Tab::ALL[(self.index() + Tab::ALL.len() - 1) % Tab::ALL.len()]
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Filter {
    Tracked,
    Followed,
    All,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThreadScope {
    Threads,
    Today,
}
impl Filter {
    pub const ALL: [Filter; 3] = [Filter::Tracked, Filter::Followed, Filter::All];

    pub fn label(self) -> &'static str {
        match self {
            Filter::Tracked => "Tracked",
            Filter::Followed => "Followed",
            Filter::All => "All",
        }
    }

    pub fn query(self) -> &'static str {
        match self {
            Filter::Tracked => "tracked",
            Filter::Followed => "followed",
            Filter::All => "all",
        }
    }

    pub fn index(self) -> usize {
        Filter::ALL
            .iter()
            .position(|item| *item == self)
            .unwrap_or(0)
    }

    pub fn next(self) -> Self {
        Filter::ALL[(self.index() + 1) % Filter::ALL.len()]
    }

    pub fn previous(self) -> Self {
        Filter::ALL[(self.index() + Filter::ALL.len() - 1) % Filter::ALL.len()]
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Level {
    Good,
    Info,
    Warn,
    Error,
    Muted,
}

#[derive(Debug, Clone)]
pub struct ActivityLine {
    pub at: i64,
    pub level: Level,
    pub text: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChatFocus {
    List,
    Composer,
}

#[derive(Debug, Clone, Default)]
pub struct InputState {
    pub text: String,
    pub cursor: usize,
}

impl InputState {
    pub fn set(&mut self, text: impl Into<String>) {
        self.text = text.into();
        self.cursor = self.text.len();
    }

    pub fn take(&mut self) -> String {
        self.cursor = 0;
        std::mem::take(&mut self.text)
    }

    pub fn clear(&mut self) {
        self.cursor = 0;
        self.text.clear();
    }

    pub fn is_empty(&self) -> bool {
        self.text.is_empty()
    }

    pub fn insert_char(&mut self, character: char) {
        self.cursor = self.cursor.min(self.text.len());
        self.text.insert(self.cursor, character);
        self.cursor += character.len_utf8();
    }

    pub fn insert_str(&mut self, text: &str) {
        self.cursor = self.cursor.min(self.text.len());
        self.text.insert_str(self.cursor, text);
        self.cursor += text.len();
    }

    pub fn backspace(&mut self) {
        if self.cursor == 0 {
            return;
        }
        let mut index = self.cursor - 1;
        while index > 0 && !self.text.is_char_boundary(index) {
            index -= 1;
        }
        self.text.replace_range(index..self.cursor, "");
        self.cursor = index;
    }

    pub fn delete_forward(&mut self) {
        if self.cursor >= self.text.len() {
            return;
        }
        let mut index = self.cursor + 1;
        while index < self.text.len() && !self.text.is_char_boundary(index) {
            index += 1;
        }
        self.text.replace_range(self.cursor..index, "");
    }

    pub fn left(&mut self) {
        if self.cursor == 0 {
            return;
        }
        let mut index = self.cursor - 1;
        while index > 0 && !self.text.is_char_boundary(index) {
            index -= 1;
        }
        self.cursor = index;
    }

    pub fn right(&mut self) {
        if self.cursor >= self.text.len() {
            return;
        }
        let mut index = self.cursor + 1;
        while index < self.text.len() && !self.text.is_char_boundary(index) {
            index += 1;
        }
        self.cursor = index;
    }

    pub fn home(&mut self) {
        self.cursor = 0;
    }

    pub fn end(&mut self) {
        self.cursor = self.text.len();
    }

    pub fn delete_word(&mut self) {
        if self.cursor == 0 {
            return;
        }
        let chars: Vec<(usize, char)> = self.text.char_indices().collect();
        let mut position = chars
            .iter()
            .position(|(index, _)| *index >= self.cursor)
            .unwrap_or(chars.len());
        while position > 0 && chars[position - 1].1.is_whitespace() {
            position -= 1;
        }
        while position > 0 && !chars[position - 1].1.is_whitespace() {
            position -= 1;
        }
        let start = if position < chars.len() {
            chars[position].0
        } else {
            self.text.len()
        };
        self.text.replace_range(start..self.cursor, "");
        self.cursor = start;
    }
}

pub struct ChatState {
    pub store: ChatStore,
    pub draft: Option<Conversation>,
    /// Row 0 is "new thread"; rows 1.. are `store.conversations`.
    pub selected: usize,
    pub focus: ChatFocus,
    pub input: InputState,
    pub scroll: u16,
    pub follow: bool,
    pub pending: HashMap<String, String>,
    pub seen_steps: HashMap<String, HashSet<String>>,
    /// Per-conversation composer drafts, kept when jumping between threads.
    pub drafts: HashMap<String, InputState>,
}

impl ChatState {
    pub fn new(store: ChatStore) -> Self {
        Self {
            store,
            draft: None,
            selected: 0,
            focus: ChatFocus::Composer,
            input: InputState::default(),
            scroll: 0,
            follow: true,
            pending: HashMap::new(),
            seen_steps: HashMap::new(),
            drafts: HashMap::new(),
        }
    }

    pub fn current_input_key(&self) -> String {
        if self.selected == 0 {
            return "__new__".to_string();
        }
        self.store
            .conversations
            .get(self.selected - 1)
            .map(|conversation| conversation.id.clone())
            .unwrap_or_else(|| "__new__".to_string())
    }

    pub fn stash_input(&mut self) {
        let key = self.current_input_key();
        if self.input.is_empty() {
            self.drafts.remove(&key);
        } else {
            self.drafts.insert(key, self.input.clone());
        }
    }

    pub fn restore_input(&mut self) {
        let key = self.current_input_key();
        self.input = self.drafts.remove(&key).unwrap_or_default();
    }

    pub fn clear_draft_for(&mut self, key: &str) {
        self.drafts.remove(key);
    }

    pub fn row_count(&self) -> usize {
        1 + self.store.conversations.len()
    }

    pub fn selected_conversation(&self) -> Option<&Conversation> {
        if self.selected == 0 {
            self.draft.as_ref()
        } else {
            self.store.conversations.get(self.selected - 1)
        }
    }

    pub fn selected_id(&self) -> Option<String> {
        self.selected_conversation()
            .map(|conversation| conversation.id.clone())
    }

    /// Start a fresh conversation and put the cursor in the composer.
    pub fn begin_draft(&mut self, thread_key: Option<String>, title: Option<String>) {
        if self.selected > 0 {
            self.stash_input();
        } else {
            // A new thread starts blank; an abandoned new-thread draft is not
            // restored by this action.
            self.drafts.remove("__new__");
        }
        if let Some(draft) = self.draft.take() {
            if !draft.is_empty() {
                self.store.insert(draft);
                self.store.save();
            }
        }
        self.draft = Some(Conversation::draft(thread_key, title));
        self.selected = 0;
        self.input.clear();
        self.focus = ChatFocus::Composer;
        self.scroll = 0;
        self.follow = true;
    }

    pub fn select(&mut self, index: usize) {
        self.stash_input();
        let last = self.row_count().saturating_sub(1);
        self.selected = index.min(last);
        if self.selected > 0 {
            if let Some(draft) = self.draft.take() {
                if !draft.is_empty() {
                    self.store.insert(draft);
                    self.store.save();
                }
            }
        }
        self.restore_input();
        self.scroll = 0;
        self.follow = true;
    }

    pub fn select_by_id(&mut self, id: &str) -> bool {
        let Some(index) = self
            .store
            .conversations
            .iter()
            .position(|conversation| conversation.id == id)
        else {
            return false;
        };
        self.select(index + 1);
        true
    }

    pub fn move_selection(&mut self, delta: isize) {
        let last = self.row_count().saturating_sub(1) as isize;
        let next = (self.selected as isize + delta).clamp(0, last);
        self.select(next as usize);
    }

    /// Commit the draft if needed and append the user message.
    /// Returns `(conversation id, prior transcript, thread key)`.
    pub fn prepare_send(&mut self, text: &str) -> Result<(String, String, Option<String>), String> {
        if self.selected == 0 {
            if self.draft.is_none() {
                self.begin_draft(None, None);
            }
            let mut conversation = self
                .draft
                .take()
                .unwrap_or_else(|| Conversation::draft(None, None));
            let transcript = conversation.transcript();
            conversation.push_user(text);
            conversation.pending_job = Some(PENDING_SENTINEL.to_string());
            let id = conversation.id.clone();
            let thread_key = conversation.thread_key.clone();
            self.store.insert(conversation);
            self.selected = self
                .store
                .conversations
                .iter()
                .position(|conversation| conversation.id == id)
                .map(|index| index + 1)
                .unwrap_or(0);
            self.pending
                .insert(id.clone(), PENDING_SENTINEL.to_string());
            self.store.save();
            Ok((id, transcript, thread_key))
        } else {
            let index = self.selected - 1;
            let conversation = self
                .store
                .conversations
                .get_mut(index)
                .ok_or_else(|| "that conversation disappeared".to_string())?;
            if conversation.is_pending() {
                return Err(
                    "Hermes is still answering this thread — wait or press Ctrl+X to cancel"
                        .to_string(),
                );
            }
            let transcript = conversation.transcript();
            conversation.push_user(text);
            conversation.pending_job = Some(PENDING_SENTINEL.to_string());
            let id = conversation.id.clone();
            let thread_key = conversation.thread_key.clone();
            self.pending
                .insert(id.clone(), PENDING_SENTINEL.to_string());
            self.store.save();
            Ok((id, transcript, thread_key))
        }
    }

    pub fn active_job(&self, id: &str) -> Option<String> {
        self.pending
            .get(id)
            .filter(|job| job.as_str() != PENDING_SENTINEL)
            .cloned()
            .or_else(|| {
                self.store
                    .get(id)
                    .and_then(|conversation| conversation.pending_job.clone())
                    .filter(|job| job != PENDING_SENTINEL)
            })
    }
}

pub struct ThreadsState {
    pub filter: Filter,
    pub raw: Vec<Value>,
    pub views: Vec<ThreadView>,
    pub entries: Vec<Entry>,
    pub selected: usize,
    pub expanded: HashSet<String>,
    pub grouping: bool,
    pub search: String,
    pub loading: bool,
    pub loaded: bool,
    pub detail_scroll: u16,
    /// Only threads with activity since local midnight (the Today tab).
    pub today_only: bool,
}

impl Default for ThreadsState {
    fn default() -> Self {
        Self {
            filter: Filter::Tracked,
            raw: Vec::new(),
            views: Vec::new(),
            entries: Vec::new(),
            selected: 0,
            expanded: HashSet::new(),
            grouping: true,
            search: String::new(),
            loading: false,
            loaded: false,
            detail_scroll: 0,
            today_only: false,
        }
    }
}

impl ThreadsState {
    pub fn today() -> Self {
        Self {
            filter: Filter::All,
            today_only: true,
            // Recent activity is easier to scan one thread per row; grouping
            // stays available on the Threads tab.
            grouping: false,
            ..Self::default()
        }
    }

    pub fn rebuild(&mut self) {
        let previous = self.selected_entry().map(|entry| entry.key.clone());
        self.views = model::visible_views(&self.raw, &self.search);
        if self.today_only {
            let cutoff = model::seconds_since_local_midnight();
            self.views
                .retain(|view| view.age_seconds.map(|age| age <= cutoff).unwrap_or(false));
        }
        self.entries = model::build_entries(&self.views, self.grouping, &self.expanded);
        if let Some(previous) = previous {
            if let Some(index) = self.entries.iter().position(|entry| entry.key == previous) {
                self.selected = index;
            }
        }
        self.clamp_selection();
    }

    fn clamp_selection(&mut self) {
        if self.entries.is_empty() {
            self.selected = 0;
        } else {
            self.selected = self.selected.min(self.entries.len() - 1);
        }
    }

    pub fn selected_entry(&self) -> Option<&Entry> {
        self.entries.get(self.selected)
    }

    pub fn selected_thread_key(&self) -> Option<String> {
        self.selected_entry()
            .map(|entry| entry.thread_key().to_string())
            .filter(|key| !key.is_empty())
    }

    pub fn move_selection(&mut self, delta: isize) {
        if self.entries.is_empty() {
            return;
        }
        let last = self.entries.len() as isize - 1;
        self.selected = (self.selected as isize + delta).clamp(0, last) as usize;
        self.detail_scroll = 0;
    }

    pub fn first(&mut self) {
        self.selected = 0;
        self.detail_scroll = 0;
    }

    pub fn last(&mut self) {
        self.selected = self.entries.len().saturating_sub(1);
        self.detail_scroll = 0;
    }

    pub fn toggle_group(&mut self) -> bool {
        let Some(entry) = self.selected_entry() else {
            return false;
        };
        if !entry.is_group() {
            return false;
        }
        let topic = entry.topic.clone();
        if !self.expanded.remove(&topic) {
            self.expanded.insert(topic);
        }
        self.rebuild();
        true
    }

    pub fn select_key(&mut self, key: &str) -> bool {
        let Some(index) = self
            .entries
            .iter()
            .position(|entry| entry.key == key || entry.thread_key() == key)
        else {
            return false;
        };
        self.selected = index;
        self.detail_scroll = 0;
        true
    }

    /// Select a concrete thread key, expanding its topic group first when the
    /// list is grouped so the child row exists.
    pub fn select_thread(&mut self, key: &str) -> bool {
        if let Some(view) = self.views.iter().find(|view| view.key == key) {
            let topic = view.topic.trim().to_string();
            if !topic.is_empty() && self.expanded.insert(topic) {
                self.rebuild();
            }
        }
        self.select_key(key)
    }
}

#[derive(Debug, Clone)]
pub struct JobSummary {
    pub id: String,
    pub status: String,
    pub title: String,
    pub raw: Value,
}

#[derive(Default)]
pub struct JobsState {
    pub jobs: Vec<JobSummary>,
    pub selected: usize,
    pub loading: bool,
}

impl JobsState {
    pub fn selected(&self) -> Option<&JobSummary> {
        self.jobs.get(self.selected)
    }

    pub fn move_selection(&mut self, delta: isize) {
        if self.jobs.is_empty() {
            return;
        }
        let last = self.jobs.len() as isize - 1;
        self.selected = (self.selected as isize + delta).clamp(0, last) as usize;
    }

    pub fn apply(&mut self, raw: Vec<Value>) {
        let previous = self.selected().map(|job| job.id.clone());
        self.jobs = raw
            .iter()
            .map(|job| JobSummary {
                id: model::job_id(job),
                status: model::job_status(job),
                title: model::job_title(job),
                raw: job.clone(),
            })
            .collect();
        if let Some(previous) = previous {
            if let Some(index) = self.jobs.iter().position(|job| job.id == previous) {
                self.selected = index;
            }
        }
        if !self.jobs.is_empty() {
            self.selected = self.selected.min(self.jobs.len() - 1);
        }
    }

    pub fn running(&self) -> usize {
        self.jobs
            .iter()
            .filter(|job| matches!(job.status.as_str(), "running" | "pending" | "queued"))
            .count()
    }
}

#[derive(Default)]
pub struct CommandState {
    pub open: bool,
    pub search: bool,
    pub input: InputState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChoiceAction {
    Snooze,
    Remind,
}

pub struct ChoiceState {
    pub title: String,
    pub options: Vec<(String, String)>,
    pub selected: usize,
    pub action: ChoiceAction,
}

pub enum ConfirmAction {
    DeleteConversation(String),
}

pub struct ConfirmState {
    pub title: String,
    pub body: String,
    pub action: ConfirmAction,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JumpKind {
    Chat,
    Thread,
}

impl JumpKind {
    pub fn label(self) -> &'static str {
        match self {
            JumpKind::Chat => "CHAT",
            JumpKind::Thread => "THREAD",
        }
    }
}

#[derive(Debug, Clone)]
pub enum JumpTarget {
    Conversation(String),
    Thread(String),
}

#[derive(Debug, Clone)]
pub struct JumpEntry {
    pub title: String,
    pub meta: String,
    pub kind: JumpKind,
    pub target: JumpTarget,
}

#[derive(Default)]
pub struct JumpState {
    pub query: InputState,
    pub selected: usize,
    pub all: Vec<JumpEntry>,
    pub filtered: Vec<usize>,
}

impl JumpState {
    pub fn new(all: Vec<JumpEntry>, preselect: Option<&JumpTarget>) -> Self {
        let mut state = Self {
            query: InputState::default(),
            selected: 0,
            filtered: (0..all.len()).collect(),
            all,
        };
        if let Some(target) = preselect {
            if let Some(index) = state
                .all
                .iter()
                .position(|entry| same_target(&entry.target, target))
            {
                state.selected = index;
            }
        }
        state
    }

    pub fn rebuild(&mut self) {
        let needle = self.query.text.trim().to_lowercase();
        self.filtered = self
            .all
            .iter()
            .enumerate()
            .filter(|(_, entry)| {
                needle.is_empty()
                    || entry.title.to_lowercase().contains(&needle)
                    || entry.meta.to_lowercase().contains(&needle)
                    || match &entry.target {
                        JumpTarget::Conversation(id) => id.to_lowercase().contains(&needle),
                        JumpTarget::Thread(key) => key.to_lowercase().contains(&needle),
                    }
            })
            .map(|(index, _)| index)
            .collect();
        if self.filtered.is_empty() {
            self.selected = 0;
        } else {
            self.selected = self.selected.min(self.filtered.len() - 1);
        }
    }

    pub fn selected_entry(&self) -> Option<&JumpEntry> {
        self.filtered
            .get(self.selected)
            .and_then(|index| self.all.get(*index))
    }

    pub fn move_selection(&mut self, delta: isize) {
        if self.filtered.is_empty() {
            return;
        }
        let last = self.filtered.len() as isize - 1;
        self.selected = (self.selected as isize + delta).clamp(0, last) as usize;
    }
}

fn same_target(left: &JumpTarget, right: &JumpTarget) -> bool {
    match (left, right) {
        (JumpTarget::Conversation(a), JumpTarget::Conversation(b)) => a == b,
        (JumpTarget::Thread(a), JumpTarget::Thread(b)) => a == b,
        _ => false,
    }
}

pub enum AppEvent {
    Input(KeyEvent),
    Paste(String),
    Tick,
    Threads {
        scope: ThreadScope,
        filter: Filter,
        result: Result<Vec<Value>, String>,
    },
    Jobs(Result<Vec<Value>, String>),
    Stream {
        connected: bool,
        error: Option<String>,
    },
    Server(Value),
    Command {
        line: String,
        result: CommandResult,
    },
    Ask {
        conversation: String,
        job_id: Option<String>,
        error: Option<String>,
    },
    ChatJob {
        conversation: String,
        steps: Vec<JobStep>,
        done: bool,
        ok: bool,
        result: String,
        error: String,
        status: String,
    },
    Action(Result<String, String>),
}

pub struct App {
    pub api: Option<Api>,
    pub config_error: Option<String>,
    pub tab: Tab,
    pub chat: ChatState,
    pub threads: ThreadsState,
    pub today: ThreadsState,
    pub jobs: JobsState,
    pub connected: Option<bool>,
    pub banner: Option<String>,
    pub help: bool,
    pub help_scroll: u16,
    pub choice: Option<ChoiceState>,
    pub confirm: Option<ConfirmState>,
    pub jump: Option<JumpState>,
    pub prefix_at: Option<Instant>,
    pub command: CommandState,
    pub activity: Vec<ActivityLine>,
    pub toast: Option<(String, Level, Instant)>,
    pub spinner: usize,
    pub last_event_id: i64,
    pub should_quit: bool,
    pub unread: u64,
    tx: Sender<AppEvent>,
    rx: Receiver<AppEvent>,
    stream_stop: Arc<AtomicBool>,
    refreshing_threads: bool,
    refreshing_today: bool,
    refreshing_jobs: bool,
    threads_dirty: bool,
    today_dirty: bool,
    threads_fetched_at: Option<Instant>,
    today_fetched_at: Option<Instant>,
    jobs_fetched_at: Option<Instant>,
    unread_at: Option<Instant>,
    pending_thread: Option<String>,
    next_mode: String,
}

impl App {
    pub fn bootstrap(tx: Sender<AppEvent>, rx: Receiver<AppEvent>) -> Self {
        let store = ChatStore::load();
        let mut app = Self {
            api: None,
            config_error: None,
            tab: Tab::Chat,
            chat: ChatState::new(store),
            threads: ThreadsState::default(),
            today: ThreadsState::today(),
            jobs: JobsState::default(),
            connected: None,
            banner: None,
            help: false,
            help_scroll: 0,
            choice: None,
            confirm: None,
            jump: None,
            prefix_at: None,
            command: CommandState::default(),
            activity: Vec::new(),
            toast: None,
            spinner: 0,
            last_event_id: 0,
            should_quit: false,
            unread: 0,
            tx,
            rx,
            stream_stop: Arc::new(AtomicBool::new(false)),
            refreshing_threads: false,
            refreshing_today: false,
            refreshing_jobs: false,
            threads_dirty: false,
            today_dirty: false,
            threads_fetched_at: None,
            today_fetched_at: None,
            jobs_fetched_at: None,
            unread_at: None,
            pending_thread: None,
            next_mode: "ask".to_string(),
        };

        // Open on a fresh, ready-to-type thread: the easiest possible path from
        // "launch hermes-tui" to a conversation.
        app.begin_thread(None, None);
        app.chat.scroll = 0;

        match config::load() {
            Ok(config) => {
                let api = Api::new(&config);
                app.api = Some(api.clone());
                app.last_event_id = store::last_event_id();
                app.log(
                    Level::Muted,
                    format!("hermes-tui ready · {}", config.api_url),
                );
                app.resume_pending_jobs();
                app.start_stream();
                app.refresh_threads();
                app.refresh_today();
                app.refresh_jobs();
                app.unread = store::unread();
                app.unread_at = Some(Instant::now());
            }
            Err(error) => {
                app.config_error = Some(error.to_string());
                app.banner = Some(format!("not configured: {error}"));
                app.log(Level::Error, format!("not configured: {error}"));
            }
        }
        app
    }

    pub fn receiver(&self) -> &Receiver<AppEvent> {
        &self.rx
    }

    pub fn stop(&self) {
        self.stream_stop.store(true, Ordering::Relaxed);
    }

    // -- helpers ----------------------------------------------------------

    fn spawn<F>(&self, name: &str, task: F)
    where
        F: FnOnce() -> AppEvent + Send + 'static,
    {
        let tx = self.tx.clone();
        let _ = std::thread::Builder::new()
            .name(name.to_string())
            .spawn(move || {
                let event = task();
                let _ = tx.send(event);
            });
    }

    pub fn log(&mut self, level: Level, text: impl Into<String>) {
        let text = text.into();
        for line in text.lines() {
            let line = line.trim_end();
            if line.is_empty() {
                continue;
            }
            self.activity.push(ActivityLine {
                at: chrono::Local::now().timestamp(),
                level,
                text: line.to_string(),
            });
        }
        if self.activity.len() > 400 {
            let drop = self.activity.len() - 400;
            self.activity.drain(0..drop);
        }
    }

    pub fn toast(&mut self, level: Level, text: impl Into<String>) {
        let text = text.into();
        self.log(level, text.clone());
        self.toast = Some((model::truncate(&text, 180), level, Instant::now()));
    }

    fn require_api(&mut self) -> Option<Api> {
        if self.api.is_some() {
            return self.api.clone();
        }
        let message = self
            .config_error
            .clone()
            .unwrap_or_else(|| "no API client configured".to_string());
        self.toast(Level::Error, format!("not configured: {message}"));
        None
    }

    fn begin_thread(&mut self, thread_key: Option<String>, title: Option<String>) {
        self.tab = Tab::Chat;
        self.chat.begin_draft(thread_key, title);
        self.next_mode = "ask".to_string();
    }

    fn active_threads(&self) -> Option<&ThreadsState> {
        match self.tab {
            Tab::Threads => Some(&self.threads),
            Tab::Today => Some(&self.today),
            _ => None,
        }
    }

    fn active_threads_mut(&mut self) -> Option<&mut ThreadsState> {
        match self.tab {
            Tab::Threads => Some(&mut self.threads),
            Tab::Today => Some(&mut self.today),
            _ => None,
        }
    }

    fn active_thread_key(&self) -> Option<String> {
        self.active_threads()
            .and_then(ThreadsState::selected_thread_key)
    }

    fn cycle_instance(&mut self, delta: isize) {
        match self.tab {
            Tab::Chat => self.chat.move_selection(delta),
            Tab::Threads => self.threads.move_selection(delta),
            Tab::Today => self.today.move_selection(delta),
            Tab::Jobs => self.jobs.move_selection(delta),
        }
    }

    fn refresh_active_threads(&mut self) {
        match self.tab {
            Tab::Today => self.refresh_today(),
            Tab::Threads => self.refresh_threads(),
            _ => {}
        }
    }

    // -- background work --------------------------------------------------

    fn start_stream(&self) {
        if let Some(api) = self.api.clone() {
            events::spawn(
                api,
                self.last_event_id,
                self.tx.clone(),
                self.stream_stop.clone(),
            );
        }
    }

    pub fn refresh_threads(&mut self) {
        if self.refreshing_threads {
            self.threads_dirty = true;
            return;
        }
        let Some(api) = self.api.clone() else {
            return;
        };
        let filter = self.threads.filter;
        self.refreshing_threads = true;
        self.threads.loading = true;
        self.threads_dirty = false;
        self.threads_fetched_at = Some(Instant::now());
        self.spawn("hermes-threads", move || AppEvent::Threads {
            scope: ThreadScope::Threads,
            filter,
            result: api
                .threads(filter.query(), 200)
                .map_err(|error| error.to_string()),
        });
    }

    pub fn refresh_today(&mut self) {
        if self.refreshing_today {
            self.today_dirty = true;
            return;
        }
        let Some(api) = self.api.clone() else {
            return;
        };
        self.refreshing_today = true;
        self.today.loading = true;
        self.today_dirty = false;
        self.today_fetched_at = Some(Instant::now());
        self.spawn("hermes-today", move || AppEvent::Threads {
            scope: ThreadScope::Today,
            filter: Filter::All,
            result: api.threads("all", 200).map_err(|error| error.to_string()),
        });
    }

    pub fn refresh_jobs(&mut self) {
        if self.refreshing_jobs {
            return;
        }
        let Some(api) = self.api.clone() else {
            return;
        };
        self.refreshing_jobs = true;
        self.jobs.loading = true;
        self.jobs_fetched_at = Some(Instant::now());
        self.spawn("hermes-jobs", move || {
            AppEvent::Jobs(api.jobs().map_err(|error| error.to_string()))
        });
    }

    fn resume_pending_jobs(&mut self) {
        let pending = self.chat.store.pending();
        let mut changed = false;
        for conversation in pending {
            let Some(job) = conversation.pending_job.clone() else {
                continue;
            };
            if job == PENDING_SENTINEL {
                if let Some(stored) = self.chat.store.get_mut(&conversation.id) {
                    stored
                        .push_error("the TUI restarted before the job id was recorded; ask again");
                }
                changed = true;
                continue;
            }
            self.chat
                .pending
                .insert(conversation.id.clone(), job.clone());
            self.watch_job(conversation.id.clone(), job);
        }
        if changed {
            self.chat.store.save();
        }
    }

    fn watch_job(&self, conversation: String, job_id: String) {
        let Some(api) = self.api.clone() else {
            return;
        };
        let tx = self.tx.clone();
        let _ = std::thread::Builder::new()
            .name("hermes-chat-job".to_string())
            .spawn(move || {
                let started = Instant::now();
                loop {
                    if let Ok(job) = api.job(&job_id) {
                        let steps = model::job_steps(&job);
                        let done = model::job_finished(&job);
                        let ok = model::job_succeeded(&job);
                        let result = model::job_result(&job);
                        let error = model::job_error(&job);
                        let status = model::job_status(&job);
                        let _ = tx.send(AppEvent::ChatJob {
                            conversation: conversation.clone(),
                            steps,
                            done,
                            ok,
                            result,
                            error,
                            status,
                        });
                        if done {
                            return;
                        }
                    }
                    if started.elapsed() > Duration::from_secs(900) {
                        let _ = tx.send(AppEvent::ChatJob {
                            conversation: conversation.clone(),
                            steps: Vec::new(),
                            done: true,
                            ok: false,
                            result: String::new(),
                            error: "timed out waiting for Hermes (15 minutes)".to_string(),
                            status: "timeout".to_string(),
                        });
                        return;
                    }
                    std::thread::sleep(Duration::from_millis(1500));
                }
            });
    }

    fn run_action(&mut self, line: &str) {
        let Some(api) = self.require_api() else {
            return;
        };
        let key = self.active_thread_key();
        let line = line.to_string();
        let captured = line.clone();
        self.spawn("hermes-action", move || AppEvent::Command {
            line: captured,
            result: commands::run(&api, &line, key.as_deref()),
        });
    }

    // -- input ------------------------------------------------------------

    pub fn handle(&mut self, event: AppEvent) {
        match event {
            AppEvent::Input(key) => self.on_key(key),
            AppEvent::Paste(text) => self.on_paste(&text),
            AppEvent::Tick => self.on_tick(),
            AppEvent::Threads {
                scope,
                filter,
                result,
            } => self.on_threads(scope, filter, result),
            AppEvent::Jobs(result) => self.on_jobs(result),
            AppEvent::Stream { connected, error } => {
                if connected {
                    self.connected = Some(true);
                    self.banner = None;
                } else if error.as_deref() == Some("event stream closed") {
                    // The server ended the stream cleanly (restart, idle
                    // timeout). The SSE thread reconnects within a second;
                    // do not call the whole API offline for that.
                    self.banner = Some("event stream reconnecting…".to_string());
                } else {
                    self.connected = Some(false);
                    self.banner = Some(format!(
                        "API unreachable — retrying ({})",
                        error.unwrap_or_else(|| "offline".to_string())
                    ));
                }
            }
            AppEvent::Server(event) => self.on_server_event(event),
            AppEvent::Command { line, result } => self.on_command(line, result),
            AppEvent::Ask {
                conversation,
                job_id,
                error,
            } => self.on_ask(conversation, job_id, error),
            AppEvent::ChatJob {
                conversation,
                steps,
                done,
                ok,
                result,
                error,
                status,
            } => self.on_chat_job(conversation, steps, done, ok, result, error, status),
            AppEvent::Action(result) => match result {
                Ok(message) => self.toast(Level::Good, message),
                Err(message) => self.toast(Level::Error, message),
            },
        }
    }

    fn on_key(&mut self, key: KeyEvent) {
        if matches!(key.kind, KeyEventKind::Release) {
            return;
        }
        let control = key.modifiers.contains(KeyModifiers::CONTROL);
        let alt = key.modifiers.contains(KeyModifiers::ALT);
        let shift = key.modifiers.contains(KeyModifiers::SHIFT);

        // Always available: quit, even from a text field.
        if control && matches!(key.code, KeyCode::Char('c')) {
            self.should_quit = true;
            return;
        }

        if self.help {
            match key.code {
                KeyCode::Esc
                | KeyCode::Char('?')
                | KeyCode::Char('q')
                | KeyCode::Enter
                | KeyCode::F(1) => self.help = false,
                KeyCode::Char('j') | KeyCode::Down => {
                    self.help_scroll = self.help_scroll.saturating_add(1)
                }
                KeyCode::Char('k') | KeyCode::Up => {
                    self.help_scroll = self.help_scroll.saturating_sub(1)
                }
                KeyCode::PageDown => self.help_scroll = self.help_scroll.saturating_add(10),
                KeyCode::PageUp => self.help_scroll = self.help_scroll.saturating_sub(10),
                KeyCode::Home => self.help_scroll = 0,
                _ => {}
            }
            return;
        }

        if self.choice.is_some() {
            self.on_choice_key(key);
            return;
        }

        if self.confirm.is_some() {
            self.on_confirm_key(key);
            return;
        }

        if self.command.open {
            self.on_command_key(key, control, alt);
            return;
        }

        if self.jump.is_some() {
            self.on_jump_key(key);
            return;
        }

        if control && matches!(key.code, KeyCode::Char('l')) {
            self.open_jump();
            return;
        }

        if self.prefix_at.is_some() {
            let handled = self.on_prefix_key(key);
            self.prefix_at = None;
            if handled {
                return;
            }
            // Never let an unrecognised prefix key trigger a list action
            // (prefix+x on the Chat list would otherwise ask to delete).
            self.toast(Level::Muted, "prefix cancelled");
            return;
        }

        if control && matches!(key.code, KeyCode::Char('b')) {
            self.prefix_at = Some(Instant::now());
            return;
        }

        // A printable key means the user is typing a message. Keep global
        // single-letter shortcuts out of the way.
        if self.tab == Tab::Chat && self.chat.focus == ChatFocus::Composer {
            self.on_composer_key(key, control, alt, shift);
            return;
        }

        match key.code {
            KeyCode::Char('q') => {
                self.should_quit = true;
                return;
            }
            KeyCode::Char('?') | KeyCode::F(1) => {
                self.help = true;
                self.help_scroll = 0;
                return;
            }
            KeyCode::Tab => {
                self.tab = self.tab.next();
                return;
            }
            KeyCode::BackTab => {
                self.tab = self.tab.previous();
                return;
            }
            KeyCode::Char('1') => {
                self.tab = Tab::Chat;
                return;
            }
            KeyCode::Char('2') => {
                self.tab = Tab::Today;
                return;
            }
            KeyCode::Char('3') => {
                self.tab = Tab::Threads;
                return;
            }
            KeyCode::Char('4') => {
                self.tab = Tab::Jobs;
                return;
            }
            KeyCode::Char(':') => {
                self.open_command("");
                return;
            }
            KeyCode::Char('n') if control => {
                self.begin_thread(None, None);
                self.toast(Level::Info, "new thread — type a message and press Enter");
                return;
            }
            _ => {}
        }

        match self.tab {
            Tab::Chat => self.on_chat_list_key(key, control),
            Tab::Today => self.on_threads_key(key, control),
            Tab::Threads => self.on_threads_key(key, control),
            Tab::Jobs => self.on_jobs_key(key, control),
        }
    }

    fn on_composer_key(&mut self, key: KeyEvent, control: bool, alt: bool, shift: bool) {
        if matches!(key.code, KeyCode::F(1)) {
            self.help = true;
            self.help_scroll = 0;
            return;
        }
        match key.code {
            KeyCode::Esc => {
                self.chat.focus = ChatFocus::List;
            }
            KeyCode::Tab => {
                self.tab = self.tab.next();
            }
            KeyCode::BackTab => {
                self.tab = self.tab.previous();
            }
            KeyCode::Enter if shift || alt => {
                self.chat.input.insert_char('\n');
            }
            KeyCode::Enter => self.send_chat(),
            KeyCode::Char('j') if control => {
                self.chat.input.insert_char('\n');
            }
            KeyCode::Char('n') if control => {
                self.begin_thread(None, None);
                self.toast(Level::Info, "new thread — type a message and press Enter");
            }
            KeyCode::Char('x') if control => self.cancel_pending(),
            KeyCode::Char('u') if control => self.chat.input.clear(),
            KeyCode::Char('w') if control => self.chat.input.delete_word(),
            KeyCode::PageUp => self.scroll_transcript(-10),
            KeyCode::PageDown => self.scroll_transcript(10),
            KeyCode::Char('c') if control => {}
            KeyCode::Backspace => self.chat.input.backspace(),
            KeyCode::Delete => self.chat.input.delete_forward(),
            KeyCode::Left => self.chat.input.left(),
            KeyCode::Right => self.chat.input.right(),
            KeyCode::Home => self.chat.input.home(),
            KeyCode::End => self.chat.input.end(),
            KeyCode::Char(character) if !control && !alt => {
                self.chat.input.insert_char(character);
            }
            _ => {}
        }
    }

    fn on_chat_list_key(&mut self, key: KeyEvent, control: bool) {
        match key.code {
            KeyCode::Char('j') | KeyCode::Down => self.chat.move_selection(1),
            KeyCode::Char('k') | KeyCode::Up => self.chat.move_selection(-1),
            KeyCode::Char('g') | KeyCode::Home => self.chat.select(0),
            KeyCode::Char('G') | KeyCode::End => {
                let last = self.chat.row_count().saturating_sub(1);
                self.chat.select(last)
            }
            KeyCode::Char('n') => {
                self.begin_thread(None, None);
                self.toast(Level::Info, "new thread — type a message and press Enter");
            }
            KeyCode::Enter => {
                if self.chat.selected == 0 && self.chat.draft.is_none() {
                    self.chat.begin_draft(None, None);
                }
                self.chat.focus = ChatFocus::Composer;
            }
            KeyCode::Char('i') | KeyCode::Char('a') if !control => {
                self.chat.focus = ChatFocus::Composer;
            }
            KeyCode::Char('x') => self.ask_delete_conversation(),
            KeyCode::PageUp => self.scroll_transcript(-10),
            KeyCode::PageDown => self.scroll_transcript(10),
            KeyCode::Char('r') if control => self.chat.store.save(),
            KeyCode::Char(':') => self.open_command(""),
            KeyCode::Char('?') => {
                self.help = true;
                self.help_scroll = 0;
            }
            KeyCode::Char('1') => self.tab = Tab::Chat,
            KeyCode::Char('2') => self.tab = Tab::Today,
            KeyCode::Char('3') => self.tab = Tab::Threads,
            KeyCode::Char('4') => self.tab = Tab::Jobs,
            KeyCode::Char('q') => self.should_quit = true,
            _ => {}
        }
    }

    fn on_threads_key(&mut self, key: KeyEvent, _control: bool) {
        let today = self.tab == Tab::Today;
        match key.code {
            KeyCode::Char('j') | KeyCode::Down => {
                if let Some(state) = self.active_threads_mut() {
                    state.move_selection(1);
                }
            }
            KeyCode::Char('k') | KeyCode::Up => {
                if let Some(state) = self.active_threads_mut() {
                    state.move_selection(-1);
                }
            }
            KeyCode::Char('g') | KeyCode::Home => {
                if let Some(state) = self.active_threads_mut() {
                    state.first();
                }
            }
            KeyCode::Char('G') | KeyCode::End => {
                if let Some(state) = self.active_threads_mut() {
                    state.last();
                }
            }
            KeyCode::PageDown => {
                if let Some(state) = self.active_threads_mut() {
                    state.move_selection(8);
                }
            }
            KeyCode::PageUp => {
                if let Some(state) = self.active_threads_mut() {
                    state.move_selection(-8);
                }
            }
            KeyCode::Char(' ') => {
                if let Some(state) = self.active_threads_mut() {
                    state.toggle_group();
                }
            }
            KeyCode::Enter | KeyCode::Char('o') => self.open_selected_link(),
            KeyCode::Char('y') => self.copy_selected_link(),
            KeyCode::Char('d') => self.run_action("done"),
            KeyCode::Char('i') => self.run_action("important"),
            KeyCode::Char('f') => {
                let followed = self
                    .active_threads()
                    .and_then(ThreadsState::selected_entry)
                    .map(|entry| entry.view.followed)
                    .unwrap_or(true);
                self.run_action(if followed { "unfollow" } else { "follow" });
            }
            KeyCode::Char('s') => self.open_snooze_choice(),
            KeyCode::Char('R') => self.open_remind_choice(),
            KeyCode::Char('t') => self.open_command("track "),
            KeyCode::Char('a') => self.ask_about_selected_thread(),
            KeyCode::Char('[') | KeyCode::Char(']') if today => {
                self.toast(
                    Level::Muted,
                    "Today always shows all threads; use the Threads tab to filter",
                );
            }
            KeyCode::Char('[') => {
                self.threads.filter = self.threads.filter.previous();
                self.threads.loaded = false;
                self.refresh_threads();
            }
            KeyCode::Char(']') => {
                self.threads.filter = self.threads.filter.next();
                self.threads.loaded = false;
                self.refresh_threads();
            }
            KeyCode::Char('/') => self.open_search(),
            KeyCode::Char(':') => self.open_command(""),
            KeyCode::Char('r') => self.refresh_active_threads(),
            KeyCode::Char('?') => {
                self.help = true;
                self.help_scroll = 0;
            }
            KeyCode::Esc => {
                let cleared = if let Some(state) = self.active_threads_mut() {
                    if state.search.is_empty() {
                        false
                    } else {
                        state.search.clear();
                        state.rebuild();
                        true
                    }
                } else {
                    false
                };
                if cleared {
                    self.toast(Level::Muted, "filter cleared");
                }
            }
            KeyCode::Char('1') => self.tab = Tab::Chat,
            KeyCode::Char('2') => self.tab = Tab::Today,
            KeyCode::Char('3') => self.tab = Tab::Threads,
            KeyCode::Char('4') => self.tab = Tab::Jobs,
            KeyCode::Char('q') => self.should_quit = true,
            _ => {}
        }
    }

    fn on_jobs_key(&mut self, key: KeyEvent, _control: bool) {
        match key.code {
            KeyCode::Char('j') | KeyCode::Down => self.jobs.move_selection(1),
            KeyCode::Char('k') | KeyCode::Up => self.jobs.move_selection(-1),
            KeyCode::Char('g') | KeyCode::Home => self.jobs.selected = 0,
            KeyCode::Char('G') | KeyCode::End => {
                self.jobs.selected = self.jobs.jobs.len().saturating_sub(1)
            }
            KeyCode::Char('c') => self.cancel_selected_job(),
            KeyCode::Char('r') => self.refresh_jobs(),
            KeyCode::Char(':') => self.open_command(""),
            KeyCode::Char('?') => {
                self.help = true;
                self.help_scroll = 0;
            }
            KeyCode::Char('1') => self.tab = Tab::Chat,
            KeyCode::Char('2') => self.tab = Tab::Today,
            KeyCode::Char('3') => self.tab = Tab::Threads,
            KeyCode::Char('4') => self.tab = Tab::Jobs,
            KeyCode::Char('q') => self.should_quit = true,
            _ => {}
        }
    }

    fn on_command_key(&mut self, key: KeyEvent, control: bool, _alt: bool) {
        if matches!(key.code, KeyCode::F(1)) {
            self.help = true;
            self.help_scroll = 0;
            return;
        }
        match key.code {
            KeyCode::Esc => {
                self.command.open = false;
                self.command.input.clear();
            }
            KeyCode::Enter => self.submit_command(),
            KeyCode::Char('u') if control => self.command.input.clear(),
            KeyCode::Char('w') if control => self.command.input.delete_word(),
            KeyCode::Backspace => self.command.input.backspace(),
            KeyCode::Delete => self.command.input.delete_forward(),
            KeyCode::Left => self.command.input.left(),
            KeyCode::Right => self.command.input.right(),
            KeyCode::Home => self.command.input.home(),
            KeyCode::End => self.command.input.end(),
            KeyCode::Char(character) if !control => self.command.input.insert_char(character),
            _ => {}
        }
    }

    fn on_paste(&mut self, text: &str) {
        if self.command.open {
            self.command.input.insert_str(text);
        } else if let Some(jump) = self.jump.as_mut() {
            jump.query.insert_str(text);
            jump.rebuild();
        } else if self.tab == Tab::Chat && self.chat.focus == ChatFocus::Composer {
            self.chat.input.insert_str(text);
        }
    }

    // -- chat -------------------------------------------------------------

    fn send_chat(&mut self) {
        let input_key = self.chat.current_input_key();
        let text = self.chat.input.take().trim().to_string();
        if text.is_empty() {
            return;
        }
        let Some(api) = self.require_api() else {
            self.chat.input.set(text);
            return;
        };
        let prepared = self.chat.prepare_send(&text);
        let (conversation, transcript, thread_key) = match prepared {
            Ok(prepared) => prepared,
            Err(error) => {
                self.chat.input.set(text);
                self.toast(Level::Warn, error);
                return;
            }
        };
        self.chat.clear_draft_for(&input_key);
        let mode = if self.next_mode.is_empty() {
            "ask".to_string()
        } else {
            std::mem::take(&mut self.next_mode)
        };
        // Follow-up messages are ordinary questions with the conversation (and
        // any attached thread) as context; investigate/draft only applies to
        // the message that requested it.
        self.next_mode = "ask".to_string();
        self.chat.scroll = 0;
        self.chat.follow = true;
        let question = text.clone();
        self.spawn("hermes-ask", move || {
            let result = api.ask(&question, thread_key.as_deref(), &transcript, &mode, "auto");
            match result {
                Ok(value) => AppEvent::Ask {
                    conversation,
                    job_id: extract_job_id(&value),
                    error: None,
                },
                Err(error) => AppEvent::Ask {
                    conversation,
                    job_id: None,
                    error: Some(error.to_string()),
                },
            }
        });
    }

    fn on_ask(&mut self, conversation: String, job_id: Option<String>, error: Option<String>) {
        if let Some(error) = error {
            if let Some(stored) = self.chat.store.get_mut(&conversation) {
                stored.push_error(error.clone());
            }
            self.chat.pending.remove(&conversation);
            self.chat.store.save();
            self.toast(Level::Error, format!("ask failed: {error}"));
            return;
        }
        let Some(job_id) = job_id else {
            if let Some(stored) = self.chat.store.get_mut(&conversation) {
                stored.push_error("Hermes did not return a job id");
            }
            self.chat.pending.remove(&conversation);
            self.chat.store.save();
            self.toast(Level::Warn, "Hermes did not return a job id");
            return;
        };
        if let Some(stored) = self.chat.store.get_mut(&conversation) {
            stored.pending_job = Some(job_id.clone());
        }
        self.chat
            .pending
            .insert(conversation.clone(), job_id.clone());
        self.chat.store.save();
        self.log(Level::Muted, format!("job {job_id} started"));
        self.watch_job(conversation, job_id);
    }

    #[allow(clippy::too_many_arguments)]
    fn on_chat_job(
        &mut self,
        conversation: String,
        steps: Vec<JobStep>,
        done: bool,
        ok: bool,
        result: String,
        error: String,
        status: String,
    ) {
        {
            let ChatState {
                store,
                seen_steps,
                pending,
                ..
            } = &mut self.chat;
            let Some(stored) = store.get_mut(&conversation) else {
                return;
            };
            // A cancelled or replaced job may still be polling; ignore it once
            // the conversation no longer expects an answer.
            if stored.pending_job.is_none() {
                return;
            }
            let seen = seen_steps.entry(conversation.clone()).or_default();
            for (index, step) in steps.iter().enumerate() {
                let key = format!(
                    "{}|{}|{}",
                    step.ts
                        .map(|ts| format!("{ts:.3}"))
                        .unwrap_or_else(|| index.to_string()),
                    step.label,
                    step.detail
                );
                if seen.insert(key) {
                    stored.push_step(step.line());
                }
            }
            if !done {
                return;
            }
            if ok {
                let answer = if result.trim().is_empty() {
                    "(Hermes finished without an answer)".to_string()
                } else {
                    result
                };
                stored.push_assistant(answer);
            } else {
                let message = if !error.trim().is_empty() {
                    error
                } else if !result.trim().is_empty() {
                    result
                } else {
                    format!("job failed ({status})")
                };
                stored.push_error(message);
            }
            stored.pending_job = None;
            pending.remove(&conversation);
            seen_steps.remove(&conversation);
            store.save();
        }
        self.chat.follow = true;
        self.threads_dirty = true;
        self.today_dirty = true;
        if ok {
            self.toast(Level::Good, "Hermes answered");
        } else {
            self.toast(Level::Error, "Hermes job failed");
        }
        self.refresh_jobs();
    }

    fn cancel_pending(&mut self) {
        let Some(conversation) = self.chat.selected_id() else {
            return;
        };
        let Some(job) = self.chat.active_job(&conversation) else {
            self.toast(Level::Muted, "nothing is running in this thread");
            return;
        };
        let Some(api) = self.require_api() else {
            return;
        };
        let job_for_task = job.clone();
        self.spawn("hermes-cancel", move || {
            let result = api.cancel_job(&job_for_task);
            AppEvent::Action(match result {
                Ok(()) => Ok(format!("cancelled job {job_for_task}")),
                Err(error) => Err(format!("cannot cancel job: {error}")),
            })
        });
        if let Some(stored) = self.chat.store.get_mut(&conversation) {
            stored.push_error(format!("cancelled job {job}"));
        }
        self.chat.pending.remove(&conversation);
        self.chat.store.save();
    }

    fn scroll_transcript(&mut self, delta: i32) {
        self.chat.follow = false;
        let current = self.chat.scroll as i32 + delta;
        self.chat.scroll = current.max(0) as u16;
    }

    fn ask_delete_conversation(&mut self) {
        if self.chat.selected == 0 {
            self.toast(Level::Muted, "the new-thread row has nothing to delete");
            return;
        }
        let Some(conversation) = self.chat.selected_conversation() else {
            return;
        };
        let id = conversation.id.clone();
        let title = conversation.title_or_placeholder().to_string();
        self.confirm = Some(ConfirmState {
            title: "Delete conversation".to_string(),
            body: format!("\u{201c}{title}\u{201d} will be removed from this machine."),
            action: ConfirmAction::DeleteConversation(id),
        });
    }

    fn confirm_delete(&mut self, id: &str) {
        self.chat.stash_input();
        self.chat.store.remove(id);
        self.chat.pending.remove(id);
        self.chat.seen_steps.remove(id);
        self.chat.drafts.remove(id);
        self.chat.store.save();
        let last = self.chat.row_count().saturating_sub(1);
        self.chat.selected = self.chat.selected.min(last);
        self.chat.restore_input();
        self.toast(Level::Good, "conversation deleted");
    }

    fn ask_about_selected_thread(&mut self) {
        let Some(entry) = self.active_threads().and_then(ThreadsState::selected_entry) else {
            self.toast(Level::Warn, "select a thread first");
            return;
        };
        let key = entry.thread_key().to_string();
        let title = format!("About: {}", entry.view.display_title());
        self.begin_thread(Some(key.clone()), Some(model::truncate(&title, 58)));
        self.toast(Level::Info, format!("new thread about {key}"));
    }

    // -- overlays ---------------------------------------------------------

    fn open_snooze_choice(&mut self) {
        if self.active_thread_key().is_none() {
            self.toast(Level::Warn, "select a thread first");
            return;
        }
        self.choice = Some(ChoiceState {
            title: "Snooze this thread".to_string(),
            options: vec![
                ("1h".to_string(), "in an hour".to_string()),
                ("4h".to_string(), "in four hours".to_string()),
                ("1d".to_string(), "tomorrow".to_string()),
                ("3d".to_string(), "in three days".to_string()),
                ("off".to_string(), "clear the snooze".to_string()),
            ],
            selected: 0,
            action: ChoiceAction::Snooze,
        });
    }

    fn open_remind_choice(&mut self) {
        if self.active_thread_key().is_none() {
            self.toast(Level::Warn, "select a thread first");
            return;
        }
        self.choice = Some(ChoiceState {
            title: "Reminder cadence".to_string(),
            options: vec![
                ("1h".to_string(), "hourly".to_string()),
                ("6h".to_string(), "every six hours".to_string()),
                ("1d".to_string(), "daily".to_string()),
                ("3d".to_string(), "every three days".to_string()),
                ("off".to_string(), "no timed reminders".to_string()),
            ],
            selected: 0,
            action: ChoiceAction::Remind,
        });
    }

    fn on_choice_key(&mut self, key: KeyEvent) {
        let Some(choice) = self.choice.as_mut() else {
            return;
        };
        let last = choice.options.len().saturating_sub(1);
        match key.code {
            KeyCode::Esc | KeyCode::Char('q') => {
                self.choice = None;
            }
            KeyCode::Char('j') | KeyCode::Down => {
                choice.selected = (choice.selected + 1).min(last);
            }
            KeyCode::Char('k') | KeyCode::Up => {
                choice.selected = choice.selected.saturating_sub(1);
            }
            KeyCode::Enter => {
                let action = choice.action;
                let value = choice
                    .options
                    .get(choice.selected)
                    .map(|(value, _)| value.clone())
                    .unwrap_or_else(|| "off".to_string());
                self.choice = None;
                let line = match action {
                    ChoiceAction::Snooze => format!("snooze {value}"),
                    ChoiceAction::Remind => format!("remind {value}"),
                };
                self.run_action(&line);
            }
            _ => {}
        }
    }

    fn on_confirm_key(&mut self, key: KeyEvent) {
        let Some(confirm) = self.confirm.take() else {
            return;
        };
        match key.code {
            KeyCode::Char('y') | KeyCode::Char('Y') | KeyCode::Enter => match confirm.action {
                ConfirmAction::DeleteConversation(id) => self.confirm_delete(&id),
            },
            KeyCode::Esc | KeyCode::Char('n') | KeyCode::Char('N') | KeyCode::Char('q') => {}
            _ => {
                // Put the dialog back if the key was not an answer.
                self.confirm = Some(confirm);
            }
        }
    }

    // -- command bar ------------------------------------------------------

    fn open_command(&mut self, prefill: &str) {
        self.command.open = true;
        self.command.search = false;
        self.command.input.set(prefill);
    }

    fn open_search(&mut self) {
        self.command.open = true;
        self.command.search = true;
        self.command.input.clear();
    }

    fn submit_command(&mut self) {
        let line = self.command.input.take().trim().to_string();
        let search_mode = self.command.search;
        self.command.open = false;
        self.command.search = false;

        if search_mode {
            let (empty, query) = if let Some(state) = self.active_threads_mut() {
                state.search = line;
                state.rebuild();
                (state.search.is_empty(), state.search.clone())
            } else {
                (true, String::new())
            };
            if empty {
                self.toast(Level::Muted, "filter cleared");
            } else {
                self.toast(Level::Info, format!("filtering for {query:?}"));
            }
            return;
        }
        if line.is_empty() {
            return;
        }
        if line.eq_ignore_ascii_case("exit") || line.eq_ignore_ascii_case("quit") {
            self.should_quit = true;
            return;
        }
        let mut parts = line.splitn(2, char::is_whitespace);
        let raw_word = parts.next().unwrap_or_default();
        let word = raw_word.to_lowercase();
        let argument = parts.next().unwrap_or_default().trim().to_string();
        if let Some(mode) = commands::ask_mode(&word) {
            self.start_chat_command(mode, &argument);
            return;
        }
        if word == "new" || word == "chat" {
            self.begin_thread(None, None);
            self.toast(Level::Info, "new thread — type a message and press Enter");
            return;
        }
        let Some(api) = self.require_api() else {
            return;
        };
        let key = self.active_thread_key();
        let captured = line.clone();
        self.spawn("hermes-command", move || AppEvent::Command {
            line: captured.clone(),
            result: commands::run(&api, &captured, key.as_deref()),
        });
    }

    fn start_chat_command(&mut self, mode: &str, argument: &str) {
        match mode {
            "investigate" | "draft" => {
                let Some(entry) = self.active_threads().and_then(ThreadsState::selected_entry)
                else {
                    self.toast(
                        Level::Warn,
                        format!("{mode} needs a thread selected in the Threads tab"),
                    );
                    return;
                };
                let title = match mode {
                    "draft" => format!("Draft reply: {}", entry.view.display_title()),
                    _ => format!("Investigate: {}", entry.view.display_title()),
                };
                self.begin_thread(
                    Some(entry.thread_key().to_string()),
                    Some(model::truncate(&title, 58)),
                );
                self.next_mode = mode.to_string();
            }
            _ => {
                // A fresh thread unless the user is already sitting on an empty one.
                let already_empty_thread =
                    self.tab == Tab::Chat && self.chat.selected == 0 && self.chat.draft.is_some();
                if !already_empty_thread {
                    self.begin_thread(None, None);
                }
                self.next_mode = "ask".to_string();
            }
        }
        if argument.is_empty() {
            self.chat.focus = ChatFocus::Composer;
            self.toast(
                Level::Info,
                format!("{mode}: type your message and press Enter"),
            );
        } else {
            self.chat.focus = ChatFocus::Composer;
            self.chat.input.set(argument);
            self.send_chat();
        }
    }

    // -- jump / prefix ----------------------------------------------------

    fn open_jump(&mut self) {
        let preselect = match self.tab {
            Tab::Chat => self
                .chat
                .selected_conversation()
                .map(|conversation| JumpTarget::Conversation(conversation.id.clone())),
            Tab::Threads | Tab::Today => self.active_thread_key().map(JumpTarget::Thread),
            Tab::Jobs => None,
        };
        let entries = self.jump_entries();
        self.jump = Some(JumpState::new(entries, preselect.as_ref()));
        if self.today.raw.is_empty() {
            self.refresh_today();
        }
    }

    fn jump_entries(&self) -> Vec<JumpEntry> {
        let mut entries = Vec::new();
        let now = chrono::Local::now().timestamp();
        for conversation in &self.chat.store.conversations {
            let age = model::fmt_duration(Some((now - conversation.updated_at).max(0) as f64));
            let mut meta = format!("{age} · {} msgs", conversation.message_count());
            if conversation.is_pending() {
                meta.push_str(" · working");
            }
            if let Some(key) = &conversation.thread_key {
                meta.push_str(&format!(" · {key}"));
            }
            entries.push(JumpEntry {
                title: conversation.title_or_placeholder().to_string(),
                meta,
                kind: JumpKind::Chat,
                target: JumpTarget::Conversation(conversation.id.clone()),
            });
        }

        let mut views: Vec<ThreadView> = self.today.raw.iter().map(ThreadView::from_json).collect();
        model::sort_views(&mut views);
        for view in views {
            let mut meta_parts = Vec::new();
            if !view.channel_name.is_empty() {
                meta_parts.push(view.channel_name.clone());
            }
            meta_parts.push(view.kind.clone());
            meta_parts.push(view.age.clone());
            if view.waiting {
                meta_parts.push("waiting".to_string());
            }
            if view.done {
                meta_parts.push("done".to_string());
            }
            entries.push(JumpEntry {
                title: view.display_title().to_string(),
                meta: meta_parts.join(" · "),
                kind: JumpKind::Thread,
                target: JumpTarget::Thread(view.key.clone()),
            });
        }
        entries
    }

    fn rebuild_jump(&mut self) {
        let Some(current) = self.jump.take() else {
            return;
        };
        let selected_target = current.selected_entry().map(|entry| entry.target.clone());
        let mut state = JumpState::new(self.jump_entries(), selected_target.as_ref());
        state.query = current.query;
        state.rebuild();
        self.jump = Some(state);
    }

    fn on_jump_key(&mut self, key: KeyEvent) {
        let control = key.modifiers.contains(KeyModifiers::CONTROL);
        let alt = key.modifiers.contains(KeyModifiers::ALT);
        match key.code {
            KeyCode::Esc => {
                self.jump = None;
                return;
            }
            KeyCode::Enter => {
                let target = self
                    .jump
                    .as_ref()
                    .and_then(JumpState::selected_entry)
                    .map(|entry| entry.target.clone());
                self.jump = None;
                if let Some(target) = target {
                    self.apply_jump(target);
                }
                return;
            }
            KeyCode::Up => {
                if let Some(jump) = self.jump.as_mut() {
                    jump.move_selection(-1);
                }
                return;
            }
            KeyCode::Down => {
                if let Some(jump) = self.jump.as_mut() {
                    jump.move_selection(1);
                }
                return;
            }
            KeyCode::PageUp => {
                if let Some(jump) = self.jump.as_mut() {
                    jump.move_selection(-8);
                }
                return;
            }
            KeyCode::PageDown => {
                if let Some(jump) = self.jump.as_mut() {
                    jump.move_selection(8);
                }
                return;
            }
            KeyCode::Home => {
                if let Some(jump) = self.jump.as_mut() {
                    jump.selected = 0;
                }
                return;
            }
            KeyCode::End => {
                if let Some(jump) = self.jump.as_mut() {
                    jump.selected = jump.filtered.len().saturating_sub(1);
                }
                return;
            }
            _ => {}
        }
        let Some(jump) = self.jump.as_mut() else {
            return;
        };
        match key.code {
            KeyCode::Backspace => jump.query.backspace(),
            KeyCode::Delete => jump.query.delete_forward(),
            KeyCode::Left => jump.query.left(),
            KeyCode::Right => jump.query.right(),
            KeyCode::Char('a') if control => jump.query.home(),
            KeyCode::Char('e') if control => jump.query.end(),
            KeyCode::Char(character) if !control && !alt => jump.query.insert_char(character),
            _ => return,
        }
        jump.rebuild();
    }

    fn apply_jump(&mut self, target: JumpTarget) {
        match target {
            JumpTarget::Conversation(id) => {
                if self.chat.select_by_id(&id) {
                    self.tab = Tab::Chat;
                    self.chat.focus = ChatFocus::Composer;
                    let title = self
                        .chat
                        .selected_conversation()
                        .map(|conversation| conversation.title_or_placeholder().to_string())
                        .unwrap_or_default();
                    self.toast(Level::Info, format!("→ {title}"));
                } else {
                    self.toast(Level::Warn, "that conversation no longer exists");
                }
            }
            JumpTarget::Thread(key) => {
                self.tab = Tab::Threads;
                self.threads.filter = Filter::All;
                self.threads.search.clear();
                if !self.today.raw.is_empty() {
                    self.threads.raw = self.today.raw.clone();
                    self.threads.loaded = true;
                    self.threads.rebuild();
                    if !self.threads.select_thread(&key) {
                        self.pending_thread = Some(key.clone());
                        self.refresh_threads();
                    }
                } else {
                    self.threads.raw.clear();
                    self.threads.rebuild();
                    self.pending_thread = Some(key.clone());
                    self.refresh_threads();
                }
                self.toast(Level::Info, format!("→ {key}"));
            }
        }
    }

    fn on_prefix_key(&mut self, key: KeyEvent) -> bool {
        let control = key.modifiers.contains(KeyModifiers::CONTROL);
        let shift = key.modifiers.contains(KeyModifiers::SHIFT);
        match key.code {
            KeyCode::Esc => true,
            KeyCode::Char('b') if control => true,
            KeyCode::Char('a') if shift => {
                self.cycle_instance(-1);
                true
            }
            KeyCode::Char('a') => {
                self.cycle_instance(1);
                true
            }
            KeyCode::Char('A') => {
                self.cycle_instance(-1);
                true
            }
            KeyCode::Char('j') | KeyCode::Down => {
                self.cycle_instance(1);
                true
            }
            KeyCode::Char('k') | KeyCode::Up => {
                self.cycle_instance(-1);
                true
            }
            KeyCode::Char('g') => {
                self.open_jump();
                true
            }
            KeyCode::Char('c') => {
                self.begin_thread(None, None);
                true
            }
            KeyCode::Char('h') => {
                self.tab = self.tab.previous();
                true
            }
            KeyCode::Char('l') => {
                self.tab = self.tab.next();
                true
            }
            KeyCode::Char('1') => {
                self.tab = Tab::Chat;
                true
            }
            KeyCode::Char('2') => {
                self.tab = Tab::Today;
                true
            }
            KeyCode::Char('3') => {
                self.tab = Tab::Threads;
                true
            }
            KeyCode::Char('4') => {
                self.tab = Tab::Jobs;
                true
            }
            _ => false,
        }
    }

    // -- actions ----------------------------------------------------------

    fn open_selected_link(&mut self) {
        let Some(entry) = self.active_threads().and_then(ThreadsState::selected_entry) else {
            return;
        };
        if entry.is_group() {
            if let Some(state) = self.active_threads_mut() {
                state.toggle_group();
            }
            return;
        }
        let link = entry.view.link.clone();
        self.spawn("hermes-open", move || {
            AppEvent::Action(store::open_url(&link).map(|_| "opened link".to_string()))
        });
    }

    fn copy_selected_link(&mut self) {
        let Some(entry) = self.active_threads().and_then(ThreadsState::selected_entry) else {
            return;
        };
        let link = entry.view.link.clone();
        self.spawn("hermes-copy", move || {
            AppEvent::Action(store::copy_to_clipboard(&link).map(|_| "link copied".to_string()))
        });
    }

    fn cancel_selected_job(&mut self) {
        let Some(job) = self.jobs.selected() else {
            self.toast(Level::Muted, "no job selected");
            return;
        };
        let id = job.id.clone();
        let status = job.status.clone();
        if !matches!(status.as_str(), "running" | "pending" | "queued") {
            self.toast(Level::Muted, format!("job {id} is already {status}"));
            return;
        }
        let Some(api) = self.require_api() else {
            return;
        };
        let captured = id.clone();
        self.spawn("hermes-job-cancel", move || {
            AppEvent::Action(match api.cancel_job(&captured) {
                Ok(()) => Ok(format!("cancelled job {captured}")),
                Err(error) => Err(format!("cannot cancel job: {error}")),
            })
        });
    }

    // -- results ----------------------------------------------------------

    fn on_threads(
        &mut self,
        scope: ThreadScope,
        filter: Filter,
        result: Result<Vec<Value>, String>,
    ) {
        if scope == ThreadScope::Today {
            self.refreshing_today = false;
            self.today.loading = false;
            match result {
                Ok(raw) => {
                    self.today.raw = raw;
                    self.today.loaded = true;
                    self.today.rebuild();
                    self.connected = Some(true);
                    self.banner = None;
                }
                Err(error) => {
                    self.connected = Some(false);
                    self.banner = Some(format!("API unreachable — retrying ({error})"));
                    self.log(Level::Error, error);
                }
            }
            if self.today_dirty {
                self.today_dirty = false;
                self.refresh_today();
            }
            if self.jump.is_some() {
                self.rebuild_jump();
            }
            return;
        }

        self.refreshing_threads = false;
        self.threads.loading = false;
        if filter != self.threads.filter {
            self.refresh_threads();
            return;
        }
        match result {
            Ok(raw) => {
                self.threads.raw = raw;
                self.threads.loaded = true;
                self.threads.rebuild();
                if let Some(key) = self.pending_thread.take() {
                    if !self.threads.select_thread(&key) {
                        self.toast(Level::Warn, format!("thread {key} not found"));
                    }
                }
                self.connected = Some(true);
                self.banner = None;
            }
            Err(error) => {
                self.connected = Some(false);
                self.banner = Some(format!("API unreachable — retrying ({error})"));
                self.log(Level::Error, error);
            }
        }
        if self.threads_dirty {
            self.threads_dirty = false;
            self.refresh_threads();
        }
    }

    fn on_jobs(&mut self, result: Result<Vec<Value>, String>) {
        self.refreshing_jobs = false;
        self.jobs.loading = false;
        match result {
            Ok(raw) => self.jobs.apply(raw),
            Err(error) => self.log(Level::Error, format!("jobs: {error}")),
        }
    }

    fn on_command(&mut self, line: String, result: CommandResult) {
        if !line.trim().is_empty() {
            self.log(Level::Muted, format!("❯ {line}"));
        }
        if !result.output.is_empty() {
            let level = if result.error {
                Level::Error
            } else {
                Level::Info
            };
            self.log(level, result.output.clone());
            if let Some(first) = result.output.lines().next() {
                self.toast = Some((model::truncate(first, 180), level, Instant::now()));
            }
        }
        if result.help {
            self.help = true;
            self.help_scroll = 0;
        }
        if result.quit {
            self.should_quit = true;
        }
        if let Some(search) = result.search {
            let empty = if let Some(state) = self.active_threads_mut() {
                state.search = search;
                state.rebuild();
                state.search.is_empty()
            } else {
                self.tab = Tab::Threads;
                self.threads.search = search;
                self.threads.rebuild();
                self.threads.search.is_empty()
            };
            if empty {
                self.toast(Level::Muted, "filter cleared");
            }
        }
        if result.job_id.is_some() {
            self.refresh_jobs();
        }
        if result.refresh {
            self.refresh_threads();
            self.refresh_today();
            self.refresh_jobs();
        }
    }

    fn on_server_event(&mut self, event: Value) {
        if let Some(id) = event.get("id").and_then(Value::as_i64) {
            self.last_event_id = self.last_event_id.max(id);
        }
        let kind = model::as_text(event.get("type"));
        let payload = event.get("payload").cloned().unwrap_or_else(|| json!({}));
        match kind.as_str() {
            "notify" | "reminder" => {
                let title = {
                    let value = model::as_text(payload.get("title"));
                    if value.is_empty() {
                        "Still waiting".to_string()
                    } else {
                        value
                    }
                };
                let body = {
                    let value = model::as_text(payload.get("body"));
                    if value.is_empty() {
                        model::as_text(payload.get("summary"))
                    } else {
                        value
                    }
                };
                let message = if body.is_empty() {
                    title.clone()
                } else {
                    format!("{title} — {body}")
                };
                self.toast(Level::Warn, message);
            }
            "job.step" => {
                let job = model::as_text(payload.get("job_id"));
                let label = model::one_line(&model::as_text(payload.get("label")));
                let detail = model::one_line(&model::as_text(payload.get("detail")));
                let text = match (label.is_empty(), detail.is_empty()) {
                    (false, false) => format!("{label} — {detail}"),
                    (false, true) => label,
                    (true, false) => detail,
                    (true, true) => "step".to_string(),
                };
                self.log(Level::Muted, format!("✓ {job} {text}"));
            }
            "job.done" => {
                let job = model::as_text(payload.get("job_id"));
                let ok = payload.get("ok").and_then(Value::as_bool).unwrap_or(true);
                self.log(
                    if ok { Level::Good } else { Level::Error },
                    format!("job {job} {}", if ok { "done" } else { "failed" }),
                );
                self.refresh_jobs();
                self.threads_dirty = true;
                self.today_dirty = true;
            }
            "thread.update" => {
                let key = model::as_text(payload.get("key"));
                let status = model::as_text(payload.get("status"));
                self.log(Level::Muted, format!("{key} {status}"));
                self.threads_dirty = true;
                self.today_dirty = true;
            }
            other => {
                self.log(Level::Muted, other);
            }
        }
    }

    fn on_tick(&mut self) {
        self.spinner = self.spinner.wrapping_add(1);
        if self
            .toast
            .as_ref()
            .map(|(_, _, at)| at.elapsed() > TOAST_TTL)
            .unwrap_or(false)
        {
            self.toast = None;
        }
        if self
            .unread_at
            .map(|at| at.elapsed() > UNREAD_REFRESH)
            .unwrap_or(true)
        {
            self.unread = store::unread();
            self.unread_at = Some(Instant::now());
        }
        if self
            .prefix_at
            .map(|at| at.elapsed() > Duration::from_secs(3))
            .unwrap_or(false)
        {
            self.prefix_at = None;
        }
        if self.threads_dirty
            && self
                .threads_fetched_at
                .map(|at| at.elapsed() > Duration::from_secs(2))
                .unwrap_or(true)
        {
            self.refresh_threads();
        }
        if self
            .threads_fetched_at
            .map(|at| at.elapsed() > THREADS_REFRESH)
            .unwrap_or(true)
        {
            self.refresh_threads();
        }
        if self.today_dirty
            && self
                .today_fetched_at
                .map(|at| at.elapsed() > Duration::from_secs(2))
                .unwrap_or(true)
        {
            self.refresh_today();
        }
        if self
            .today_fetched_at
            .map(|at| at.elapsed() > THREADS_REFRESH)
            .unwrap_or(true)
        {
            self.refresh_today();
        }
        if self
            .jobs_fetched_at
            .map(|at| at.elapsed() > JOBS_REFRESH)
            .unwrap_or(true)
        {
            self.refresh_jobs();
        }
    }
}

fn extract_job_id(value: &Value) -> Option<String> {
    for key in ["job_id", "job", "id"] {
        let text = model::as_text(value.get(key));
        if !text.is_empty() {
            return Some(text);
        }
    }
    None
}

#[cfg(test)]
impl App {
    /// A deterministic app with no network threads, for rendering tests.
    pub fn test_app() -> Self {
        let (tx, rx) = std::sync::mpsc::channel();
        let mut chat = ChatState::new(ChatStore::default());
        let mut conversation = Conversation::draft(None, Some("dLocal SAML thread".to_string()));
        conversation.push_user("Why is the dLocal login failing?");
        conversation.push_step("reading the thread");
        conversation.push_assistant("The SAML assertion is rejected for the customer tenant.");
        chat.store.insert(conversation);
        chat.select(1);
        let mut app = Self {
            api: None,
            config_error: None,
            tab: Tab::Chat,
            chat,
            threads: ThreadsState::default(),
            today: ThreadsState::today(),
            jobs: JobsState::default(),
            connected: Some(true),
            banner: None,
            help: false,
            help_scroll: 0,
            choice: None,
            confirm: None,
            jump: None,
            prefix_at: None,
            command: CommandState::default(),
            activity: vec![ActivityLine {
                at: chrono::Local::now().timestamp(),
                level: Level::Muted,
                text: "hermes ready".to_string(),
            }],
            toast: None,
            spinner: 0,
            last_event_id: 0,
            should_quit: false,
            unread: 2,
            tx,
            rx,
            stream_stop: Arc::new(AtomicBool::new(false)),
            refreshing_threads: false,
            refreshing_today: false,
            refreshing_jobs: false,
            threads_dirty: false,
            today_dirty: false,
            threads_fetched_at: None,
            today_fetched_at: None,
            jobs_fetched_at: None,
            unread_at: None,
            pending_thread: None,
            next_mode: "ask".to_string(),
        };
        app.threads.raw = vec![
            json!({
                "key": "C1:1.0",
                "summary": "dLocal SAML login failure needs an answer",
                "headline": "dLocal SAML login fails — customer answer needed",
                "topic": "dlocal-saml-login",
                "channel_name": "aaa-internal",
                "kind": "slack",
                "priority": 2,
                "urgency": 92,
                "relevance": 88,
                "waiting_on_you": true,
                "idle_seconds": 3600,
                "cadence_label": "1d",
                "link": "https://example.test/one",
            }),
            json!({
                "key": "C1:2.0",
                "summary": "dLocal SAML retry",
                "topic": "dlocal-saml-login",
                "channel_name": "aaa-internal",
                "kind": "slack",
                "priority": 3,
                "urgency": 74,
                "idle_seconds": 7200,
            }),
            json!({
                "key": "CX-12",
                "summary": "Jira incident review",
                "kind": "jira",
                "priority": 3,
                "urgency": 20,
                "idle_seconds": 600,
            }),
        ];
        app.today.raw = app.threads.raw.clone();
        app.today.loaded = true;
        app.today.rebuild();
        app.threads.loaded = true;
        app.threads.rebuild();
        app.jobs.apply(vec![
            json!({
                "id": "job-1",
                "status": "running",
                "question": "what is waiting on me?",
                "steps": [{"label": "read Slack", "detail": "3 channels"}],
            }),
            json!({
                "id": "job-2",
                "status": "done",
                "question": "summarise dLocal",
                "result": "Two threads need a reply.",
            }),
        ]);
        app
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chat_rows_start_with_new_thread() {
        let mut state = ChatState::new(ChatStore::default());
        assert_eq!(state.row_count(), 1);
        assert_eq!(state.selected, 0);
        state.begin_draft(None, None);
        assert!(state.draft.is_some());
        assert_eq!(state.selected_conversation().unwrap().messages.len(), 0);
    }

    #[test]
    fn sending_commits_the_draft_and_selects_it() {
        let mut state = ChatState::new(ChatStore::default());
        state.begin_draft(None, None);
        let (id, transcript, thread_key) = state.prepare_send("what is waiting on me?").unwrap();
        assert!(transcript.is_empty());
        assert!(thread_key.is_none());
        assert_eq!(state.row_count(), 2);
        assert_eq!(state.selected, 1);
        assert_eq!(state.store.conversations[0].id, id);
        assert_eq!(state.store.conversations[0].title, "what is waiting on me?");
        assert!(state.store.conversations[0].is_pending());
    }

    #[test]
    fn pending_conversation_refuses_a_second_message() {
        let mut state = ChatState::new(ChatStore::default());
        state.begin_draft(None, None);
        state.prepare_send("first").unwrap();
        let error = state.prepare_send("second").unwrap_err();
        assert!(error.contains("still answering"));
    }

    #[test]
    fn transcript_context_is_sent_for_follow_ups() {
        let mut state = ChatState::new(ChatStore::default());
        state.begin_draft(None, None);
        let (id, _, _) = state.prepare_send("first question").unwrap();
        state
            .store
            .get_mut(&id)
            .unwrap()
            .push_assistant("first answer");
        let (_, transcript, _) = state.prepare_send("and then?").unwrap();
        assert!(transcript.contains("you: first question"));
        assert!(transcript.contains("hermes: first answer"));
    }

    #[test]
    fn filter_cycles_in_both_directions() {
        assert_eq!(Filter::Tracked.next(), Filter::Followed);
        assert_eq!(Filter::Tracked.previous(), Filter::All);
        assert_eq!(Filter::All.next(), Filter::Tracked);
    }

    #[test]
    fn today_keeps_only_threads_active_since_local_midnight() {
        let cutoff = model::seconds_since_local_midnight();
        let mut state = ThreadsState::today();
        state.raw = vec![
            json!({"key": "recent", "idle_seconds": (cutoff / 2.0).max(0.0)}),
            json!({"key": "old", "idle_seconds": cutoff + 3600.0}),
            json!({"key": "unknown"}),
        ];
        state.rebuild();
        let keys: Vec<String> = state
            .entries
            .iter()
            .map(|entry| entry.thread_key().to_string())
            .collect();
        assert!(keys.contains(&"recent".to_string()));
        assert!(!keys.contains(&"old".to_string()));
        assert!(!keys.contains(&"unknown".to_string()));
    }

    #[test]
    fn chat_drafts_follow_their_conversation() {
        let mut state = ChatState::new(ChatStore::default());
        let mut first = Conversation::draft(None, Some("first".to_string()));
        first.id = "first".to_string();
        first.push_user("hello");
        let mut second = Conversation::draft(None, Some("second".to_string()));
        second.id = "second".to_string();
        second.push_user("hello");
        state.store.insert(first);
        state.store.insert(second);

        assert!(state.select_by_id("first"));
        state.input.set("draft for first");
        assert!(state.select_by_id("second"));
        assert!(state.input.is_empty());
        state.input.set("draft for second");
        assert!(state.select_by_id("first"));
        assert_eq!(state.input.text, "draft for first");
        assert!(state.select_by_id("second"));
        assert_eq!(state.input.text, "draft for second");
    }

    #[test]
    fn jump_filters_conversations_and_threads() {
        let entries = vec![
            JumpEntry {
                title: "dLocal SAML".to_string(),
                meta: "aaa-internal · slack".to_string(),
                kind: JumpKind::Thread,
                target: JumpTarget::Thread("C1:1.0".to_string()),
            },
            JumpEntry {
                title: "Jira incident".to_string(),
                meta: "jira".to_string(),
                kind: JumpKind::Thread,
                target: JumpTarget::Thread("CX-12".to_string()),
            },
            JumpEntry {
                title: "lunch plans".to_string(),
                meta: "2 msgs".to_string(),
                kind: JumpKind::Chat,
                target: JumpTarget::Conversation("chat-1".to_string()),
            },
        ];
        let mut jump = JumpState::new(entries, None);
        assert_eq!(jump.filtered.len(), 3);
        jump.query.set("jira");
        jump.rebuild();
        assert_eq!(jump.filtered.len(), 1);
        assert_eq!(
            jump.selected_entry().unwrap().title,
            "Jira incident".to_string()
        );
    }

    #[test]
    fn prefix_and_ctrl_l_open_navigation() {
        let mut app = App::test_app();
        app.tab = Tab::Today;
        let before = app.today.selected;
        app.handle(AppEvent::Input(KeyEvent::new(
            KeyCode::Char('b'),
            KeyModifiers::CONTROL,
        )));
        assert!(app.prefix_at.is_some());
        app.handle(AppEvent::Input(KeyEvent::new(
            KeyCode::Char('a'),
            KeyModifiers::NONE,
        )));
        assert!(app.prefix_at.is_none());
        assert_eq!(app.tab, Tab::Today);
        assert_ne!(app.today.selected, before);

        app.handle(AppEvent::Input(KeyEvent::new(
            KeyCode::Char('l'),
            KeyModifiers::CONTROL,
        )));
        assert!(app.jump.is_some());
    }

    #[test]
    fn selecting_a_group_member_expands_it() {
        let mut state = ThreadsState::default();
        state.raw = vec![
            json!({"key": "one", "topic": "same", "urgency": 90}),
            json!({"key": "two", "topic": "same", "urgency": 80}),
        ];
        state.rebuild();
        assert_eq!(state.entries.len(), 1);
        assert!(state.select_thread("two"));
        assert_eq!(state.selected_entry().unwrap().thread_key(), "two");
        assert!(state.expanded.contains("same"));
    }

    #[test]
    fn tab_cycles() {
        assert_eq!(Tab::Chat.next(), Tab::Today);
        assert_eq!(Tab::Chat.previous(), Tab::Jobs);
        assert_eq!(Tab::Today.next(), Tab::Threads);
    }

    #[test]
    fn input_state_edits_unicode_safely() {
        let mut input = InputState::default();
        input.insert_char('ż');
        input.insert_char('ó');
        input.backspace();
        assert_eq!(input.text, "ż");
        assert_eq!(input.cursor, "ż".len());
        input.left();
        input.delete_forward();
        assert_eq!(input.text, "");
    }
}
