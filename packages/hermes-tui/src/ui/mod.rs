//! Rendering. Every module returns `Line`s and the app only draws state, so
//! scrolling and layout stay predictable.

mod chat;
mod help;
mod jobs;
mod jump;
mod threads;

use crate::app::{App, ChatFocus, Level, Tab};
use crate::model;
use crate::theme::{self, *};
use chrono::Local;
use ratatui::layout::{Alignment, Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Clear, Paragraph};
use ratatui::Frame;
use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};

pub fn draw(frame: &mut Frame, app: &App) {
    let area = frame.area();
    let banner_height = u16::from(app.banner.is_some());
    let command_height = if app.command.open { 3 } else { 0 };
    let chunks = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(banner_height),
        Constraint::Min(6),
        Constraint::Length(command_height),
        Constraint::Length(1),
        Constraint::Length(2),
    ])
    .split(area);

    draw_tab_bar(frame, chunks[0], app);
    if let Some(banner) = &app.banner {
        let paragraph = Paragraph::new(Line::from(vec![
            Span::styled("! ", theme::error()),
            Span::styled(banner.clone(), Style::default().fg(RED)),
        ]))
        .style(Style::default().bg(Color::Rgb(38, 19, 23)));
        frame.render_widget(paragraph, chunks[1]);
    }

    match app.tab {
        Tab::Chat => chat::draw(frame, chunks[2], app),
        Tab::Today => threads::draw(frame, chunks[2], app, &app.today, true),
        Tab::Threads => threads::draw(frame, chunks[2], app, &app.threads, false),
        Tab::Jobs => jobs::draw(frame, chunks[2], app),
    }

    if app.command.open {
        draw_command(frame, chunks[3], app);
    }
    draw_status(frame, chunks[4], app);
    draw_hints(frame, chunks[5], app);

    if app.help {
        help::draw_help(frame, area, app);
    }
    if let Some(choice) = &app.choice {
        draw_choice(frame, area, choice);
    }
    if let Some(confirm) = &app.confirm {
        draw_confirm(frame, area, confirm);
    }
    if let Some(jump) = &app.jump {
        jump::draw(frame, area, jump);
    }
}

fn draw_tab_bar(frame: &mut Frame, area: Rect, app: &App) {
    frame.render_widget(Block::default().style(theme::panel()), area);

    let mut tabs: Vec<Span> = Vec::new();
    tabs.push(Span::styled(
        " HERMES ",
        Style::default().fg(ACCENT).add_modifier(Modifier::BOLD),
    ));
    for tab in Tab::ALL {
        let selected = tab == app.tab;
        let count = match tab {
            Tab::Chat => Some(app.chat.store.conversations.len()),
            Tab::Today => app.today.loaded.then_some(app.today.views.len()),
            Tab::Threads => app.threads.loaded.then_some(app.threads.views.len()),
            Tab::Jobs => {
                let running = app.jobs.running();
                (running > 0).then_some(running)
            }
        };
        let style = if selected {
            Style::default()
                .bg(SELECT_FOCUS)
                .fg(Color::Rgb(243, 248, 245))
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(HINT)
        };
        let label = match count {
            Some(count) if count > 0 => {
                format!(" {} {} ({count}) ", tab.index() + 1, tab.title())
            }
            _ => format!(" {} {} ", tab.index() + 1, tab.title()),
        };
        tabs.push(Span::styled(label, style));
    }

    let left_width: usize = tabs.iter().map(|span| span.content.width()).sum();
    let right = status_spans(app);
    let chunks = Layout::horizontal([
        Constraint::Length((left_width as u16).min(area.width)),
        Constraint::Min(1),
    ])
    .split(area);
    frame.render_widget(
        Paragraph::new(Line::from(tabs)).style(theme::panel()),
        chunks[0],
    );
    frame.render_widget(
        Paragraph::new(Line::from(right))
            .style(theme::panel())
            .alignment(Alignment::Right),
        chunks[1],
    );
}

fn status_spans(app: &App) -> Vec<Span<'static>> {
    let mut spans = Vec::new();
    if app.config_error.is_some() {
        spans.push(Span::styled("● ", Style::default().fg(AMBER)));
        spans.push(Span::styled("not configured", Style::default().fg(AMBER)));
    } else {
        match app.connected {
            Some(true) => {
                spans.push(Span::styled("● ", theme::online()));
                spans.push(Span::styled("connected", Style::default().fg(ACCENT)));
            }
            Some(false) => {
                spans.push(Span::styled("● ", theme::error()));
                spans.push(Span::styled("offline", Style::default().fg(RED)));
            }
            None => {
                spans.push(Span::styled("● ", Style::default().fg(AMBER)));
                spans.push(Span::styled("connecting", Style::default().fg(AMBER)));
            }
        }
    }
    let waiting = app.threads.views.iter().filter(|view| view.waiting).count();
    if waiting > 0 {
        spans.push(Span::styled("   ", theme::panel()));
        spans.push(Span::styled(format!("{waiting} waiting"), theme::warning()));
    }
    if app.unread > 0 {
        spans.push(Span::styled("   ", theme::panel()));
        spans.push(Span::styled(
            format!("● {} new", app.unread),
            Style::default().fg(AMBER).add_modifier(Modifier::BOLD),
        ));
    }
    spans.push(Span::styled("   ", theme::panel()));
    spans.push(Span::styled(
        Local::now().format("%H:%M:%S").to_string(),
        Style::default().fg(FAINT),
    ));
    spans.push(Span::styled(" ", theme::panel()));
    spans
}

fn draw_status(frame: &mut Frame, area: Rect, app: &App) {
    frame.render_widget(Block::default().style(theme::panel()), area);
    let chunks = Layout::horizontal([Constraint::Min(10), Constraint::Length(9)]).split(area);
    let line = if let Some((text, level, _)) = &app.toast {
        Line::from(vec![
            Span::styled(" ", theme::panel()),
            Span::styled(symbol(*level).to_string(), style_for(*level)),
            Span::styled(" ", theme::panel()),
            Span::styled(text.clone(), style_for(*level)),
        ])
    } else {
        let (loading, scope, shown) = if app.tab == Tab::Today {
            (
                app.today.loading,
                "today".to_string(),
                app.today.views.len(),
            )
        } else {
            (
                app.threads.loading,
                app.threads.filter.label().to_lowercase(),
                app.threads.views.len(),
            )
        };
        let text = if let Some(error) = &app.config_error {
            format!("not configured — {error} (press ? for setup help)")
        } else if loading {
            format!("{} refreshing {scope}", spinner(app.spinner))
        } else {
            format!(
                "{} {} · {} threads shown · {} {}",
                app.chat.store.conversations.len(),
                if app.chat.store.conversations.len() == 1 {
                    "conversation"
                } else {
                    "conversations"
                },
                shown,
                app.jobs.jobs.len(),
                if app.jobs.jobs.len() == 1 {
                    "job"
                } else {
                    "jobs"
                }
            )
        };
        Line::from(vec![
            Span::styled(" ", theme::panel()),
            Span::styled(text, Style::default().fg(HINT)),
        ])
    };
    frame.render_widget(Paragraph::new(line).style(theme::panel()), chunks[0]);
    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::styled("F1 ", theme::key()),
            Span::styled("help ", theme::hint()),
        ]))
        .style(theme::panel())
        .alignment(Alignment::Right),
        chunks[1],
    );
}

fn draw_hints(frame: &mut Frame, area: Rect, app: &App) {
    frame.render_widget(Block::default().style(theme::panel()), area);
    let hints: Vec<(&str, &str)> = if app.help {
        vec![("j/k", "scroll"), ("esc", "close")]
    } else if app.command.open {
        vec![("enter", "run"), ("esc", "cancel"), ("ctrl+u", "clear")]
    } else if app.jump.is_some() {
        vec![
            ("type", "filter"),
            ("↑/↓", "move"),
            ("enter", "jump"),
            ("esc", "cancel"),
        ]
    } else if app.prefix_at.is_some() {
        vec![
            ("a/A", "next/prev"),
            ("1-4", "tab"),
            ("g", "jump"),
            ("c", "new chat"),
            ("h/l", "tab"),
            ("esc", "cancel"),
        ]
    } else {
        match app.tab {
            Tab::Chat if app.chat.focus == ChatFocus::Composer => vec![
                ("ctrl+l", "jump"),
                ("ctrl+b", "prefix"),
                ("enter", "send"),
                ("shift+enter", "newline"),
                ("esc", "history"),
                ("ctrl+n", "new thread"),
                ("ctrl+x", "cancel job"),
            ],
            Tab::Chat => vec![
                ("ctrl+l", "jump"),
                ("ctrl+b", "prefix"),
                ("j/k", "move"),
                ("enter", "open"),
                ("n", "new thread"),
                ("x", "delete"),
                ("ctrl+n", "new from anywhere"),
                (":", "command"),
            ],
            Tab::Today => vec![
                ("ctrl+l", "jump"),
                ("ctrl+b", "prefix"),
                ("j/k", "move"),
                ("enter", "open"),
                ("a", "ask in chat"),
                ("d", "done"),
                ("i", "important"),
                ("s", "snooze"),
                ("t", "track"),
                ("/", "search"),
                (":", "command"),
            ],
            Tab::Threads => vec![
                ("ctrl+l", "jump"),
                ("ctrl+b", "prefix"),
                ("j/k", "move"),
                ("enter", "open"),
                ("d", "done"),
                ("i", "important"),
                ("f", "follow"),
                ("s", "snooze"),
                ("R", "remind"),
                ("a", "ask in chat"),
                ("t", "track"),
                ("[ ]", "filter"),
                ("/", "search"),
                (":", "command"),
            ],
            Tab::Jobs => vec![
                ("ctrl+l", "jump"),
                ("ctrl+b", "prefix"),
                ("j/k", "move"),
                ("c", "cancel"),
                ("r", "refresh"),
                (":", "command"),
            ],
        }
    };
    let mut rows: Vec<Line> = Vec::new();
    let mut current: Vec<Span> = Vec::new();
    let mut current_width = 0usize;
    if app.prefix_at.is_some() {
        current.push(Span::styled(
            " PREFIX ",
            Style::default()
                .bg(AMBER)
                .fg(Color::Rgb(9, 13, 17))
                .add_modifier(Modifier::BOLD),
        ));
        current_width += 8;
    }
    let width = area.width as usize;
    let height = area.height as usize;
    for (keys, label) in hints {
        // Keep a shortcut and its label together: never wrap between them.
        let item_width = keys.width() + label.width() + 6;
        if current_width > 0 && current_width + item_width > width {
            rows.push(Line::from(std::mem::take(&mut current)));
            current_width = 0;
            if rows.len() >= height {
                break;
            }
        }
        current.push(Span::styled(format!(" {keys} "), theme::key_chip()));
        current.push(Span::styled(format!(" {label}   "), theme::hint()));
        current_width += item_width;
    }
    if !current.is_empty() && rows.len() < height {
        rows.push(Line::from(current));
    }
    frame.render_widget(Paragraph::new(rows).style(theme::panel()), area);
}

fn draw_command(frame: &mut Frame, area: Rect, app: &App) {
    let title = if app.command.search {
        "Search threads"
    } else {
        "Command"
    };
    let block = Block::default()
        .borders(ratatui::widgets::Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(ACCENT))
        .title(Span::styled(
            format!(" {title} "),
            Style::default().fg(ACCENT).add_modifier(Modifier::BOLD),
        ))
        .style(theme::base());
    let inner = block.inner(area);
    frame.render_widget(block, area);
    let prompt = if app.command.search { "/ " } else { ": " };
    let (visible, cursor) = tail_window(
        &app.command.input.text,
        app.command.input.cursor,
        inner.width.saturating_sub(prompt.width() as u16),
    );
    let line = Line::from(vec![
        Span::styled(prompt, theme::key()),
        Span::styled(visible, Style::default().fg(INK)),
    ]);
    frame.render_widget(Paragraph::new(line), inner);
    let cursor_x =
        (inner.x + prompt.width() as u16 + cursor).min(inner.x + inner.width.saturating_sub(1));
    frame.set_cursor_position((cursor_x, inner.y));
}

fn draw_choice(frame: &mut Frame, area: Rect, choice: &crate::app::ChoiceState) {
    let height = (choice.options.len() as u16 + 4).min(area.height);
    let width = 52.min(area.width);
    let popup = centered(area, width, height);
    frame.render_widget(Clear, popup);
    let block = Block::default()
        .borders(ratatui::widgets::Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(ACCENT))
        .title(Span::styled(
            format!(" {} ", choice.title),
            Style::default().fg(ACCENT).add_modifier(Modifier::BOLD),
        ))
        .style(theme::base());
    let inner = block.inner(popup);
    frame.render_widget(block, popup);

    let mut lines = Vec::new();
    for (index, (value, label)) in choice.options.iter().enumerate() {
        let selected = index == choice.selected;
        let style = if selected {
            Style::default()
                .bg(SELECT_FOCUS)
                .fg(Color::Rgb(243, 248, 245))
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(INK)
        };
        lines.push(Line::from(vec![
            Span::styled(if selected { " ▶ " } else { "   " }, style),
            Span::styled(format!("{value:<5}"), style),
            Span::styled(label.clone(), style),
        ]));
    }
    lines.push(Line::from(""));
    lines.push(Line::from(vec![
        Span::styled("  enter ", theme::key()),
        Span::styled("apply · ", theme::hint()),
        Span::styled("esc ", theme::key()),
        Span::styled("cancel", theme::hint()),
    ]));
    frame.render_widget(Paragraph::new(lines), inner);
}

fn draw_confirm(frame: &mut Frame, area: Rect, confirm: &crate::app::ConfirmState) {
    let popup = centered(area, 64.min(area.width), 8.min(area.height));
    frame.render_widget(Clear, popup);
    let block = Block::default()
        .borders(ratatui::widgets::Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(AMBER))
        .title(Span::styled(
            format!(" {} ", confirm.title),
            Style::default().fg(AMBER).add_modifier(Modifier::BOLD),
        ))
        .style(theme::base());
    let inner = block.inner(popup);
    frame.render_widget(block, popup);
    let lines = vec![
        Line::from(Span::styled(confirm.body.clone(), Style::default().fg(INK))),
        Line::from(""),
        Line::from(vec![
            Span::styled(" y ", theme::key()),
            Span::styled("delete  ", theme::hint()),
            Span::styled(" n / esc ", theme::key()),
            Span::styled("keep", theme::hint()),
        ]),
    ];
    frame.render_widget(Paragraph::new(lines), inner);
}

pub(crate) fn centered(area: Rect, width: u16, height: u16) -> Rect {
    let width = width.min(area.width);
    let height = height.min(area.height);
    Rect {
        x: area.x + (area.width.saturating_sub(width)) / 2,
        y: area.y + (area.height.saturating_sub(height)) / 2,
        width,
        height,
    }
}

pub(crate) fn bordered(title: impl Into<String>, accent: bool) -> Block<'static> {
    Block::default()
        .borders(ratatui::widgets::Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(if accent { ACCENT } else { BORDER }))
        .title(Span::styled(
            format!(" {} ", title.into()),
            Style::default()
                .fg(if accent { ACCENT } else { MUTED })
                .add_modifier(Modifier::BOLD),
        ))
        .style(theme::base())
}

pub(crate) fn spinner(index: usize) -> &'static str {
    const FRAMES: [&str; 10] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
    FRAMES[index % FRAMES.len()]
}

pub(crate) fn style_for(level: Level) -> Style {
    match level {
        Level::Good => Style::default().fg(ACCENT),
        Level::Info => Style::default().fg(INK),
        Level::Warn => Style::default().fg(AMBER),
        Level::Error => Style::default().fg(RED).add_modifier(Modifier::BOLD),
        Level::Muted => Style::default().fg(MUTED),
    }
}

fn symbol(level: Level) -> &'static str {
    match level {
        Level::Good => "✓",
        Level::Info => "·",
        Level::Warn => "!",
        Level::Error => "✗",
        Level::Muted => "·",
    }
}

pub(crate) fn priority_style(view: &model::ThreadView) -> Style {
    match view.priority {
        1 => Style::default().fg(RED).add_modifier(Modifier::BOLD),
        2 => Style::default().fg(AMBER).add_modifier(Modifier::BOLD),
        3 => Style::default().fg(BLUE),
        4 => Style::default().fg(MUTED),
        _ => Style::default().fg(FAINT),
    }
}

pub(crate) fn kind_style(kind: &str) -> Style {
    match kind {
        "slack" => Style::default().fg(BLUE),
        "pr" => Style::default().fg(PURPLE),
        "jira" => Style::default().fg(AMBER),
        _ => Style::default().fg(MUTED),
    }
}

pub(crate) fn score_style(value: Option<f64>) -> Style {
    match value {
        Some(value) if value >= 80.0 => Style::default().fg(RED).add_modifier(Modifier::BOLD),
        Some(value) if value >= 60.0 => Style::default().fg(AMBER).add_modifier(Modifier::BOLD),
        Some(value) if value >= 40.0 => Style::default().fg(BLUE),
        _ => Style::default().fg(FAINT),
    }
}

pub(crate) fn bar(value: Option<f64>, width: usize) -> String {
    let score = value.unwrap_or(0.0).clamp(0.0, 100.0);
    let filled = (score / 100.0 * width as f64).round() as usize;
    format!(
        "{}{}",
        "█".repeat(filled),
        "░".repeat(width.saturating_sub(filled))
    )
}

pub(crate) fn cadence_label(value: &str) -> String {
    match value {
        "" | "-" => "activity".to_string(),
        "off" => "rem off".to_string(),
        other => format!("rem {other}"),
    }
}

/// Word-wrap `text` to `width` columns, preserving explicit newlines.
pub(crate) fn wrap_text(text: &str, width: usize) -> Vec<String> {
    if width == 0 {
        return Vec::new();
    }
    let mut lines = Vec::new();
    for paragraph in text.split('\n') {
        if paragraph.is_empty() {
            lines.push(String::new());
            continue;
        }
        let mut current = String::new();
        for word in paragraph.split_whitespace() {
            let word_width = word.width();
            let current_width = current.width();
            if current.is_empty() {
                if word_width <= width {
                    current.push_str(word);
                } else {
                    let chunks = hard_wrap(word, width);
                    for (index, chunk) in chunks.iter().enumerate() {
                        if index + 1 == chunks.len() {
                            current = chunk.clone();
                        } else {
                            lines.push(chunk.clone());
                        }
                    }
                }
            } else if current_width + 1 + word_width <= width {
                current.push(' ');
                current.push_str(word);
            } else {
                lines.push(std::mem::take(&mut current));
                if word_width <= width {
                    current.push_str(word);
                } else {
                    let chunks = hard_wrap(word, width);
                    for (index, chunk) in chunks.iter().enumerate() {
                        if index + 1 == chunks.len() {
                            current = chunk.clone();
                        } else {
                            lines.push(chunk.clone());
                        }
                    }
                }
            }
        }
        if !current.is_empty() {
            lines.push(current);
        }
    }
    if lines.is_empty() {
        lines.push(String::new());
    }
    lines
}

fn hard_wrap(word: &str, width: usize) -> Vec<String> {
    let mut chunks = Vec::new();
    let mut current = String::new();
    let mut current_width = 0usize;
    for character in word.chars() {
        let char_width = character.width().unwrap_or(0);
        if current_width + char_width > width && !current.is_empty() {
            chunks.push(std::mem::take(&mut current));
            current_width = 0;
        }
        current.push(character);
        current_width += char_width;
    }
    if !current.is_empty() {
        chunks.push(current);
    }
    if chunks.is_empty() {
        chunks.push(String::new());
    }
    chunks
}

/// Fit a single line into `width` columns with an ellipsis.
pub(crate) fn fit(text: &str, width: usize) -> String {
    if width == 0 {
        return String::new();
    }
    if text.width() <= width {
        return text.to_string();
    }
    let mut out = String::new();
    let mut used = 0usize;
    for character in text.chars() {
        let char_width = character.width().unwrap_or(0);
        if used + char_width + 1 > width {
            break;
        }
        out.push(character);
        used += char_width;
    }
    out.push('…');
    out
}

/// Show the tail of a single-line input and the cursor column inside it.
fn tail_window(text: &str, cursor: usize, width: u16) -> (String, u16) {
    let width = width.max(1) as usize;
    let characters: Vec<char> = text.chars().collect();
    let cursor_chars = text[..cursor.min(text.len())].chars().count();
    let start = cursor_chars.saturating_sub(width.saturating_sub(1));
    let visible: String = characters
        .iter()
        .skip(start)
        .take(width)
        .collect::<String>();
    let column = cursor_chars
        .saturating_sub(start)
        .min(width.saturating_sub(1)) as u16;
    (visible, column)
}

/// Wrapped input text plus the visible window that keeps the cursor on screen.
pub(crate) fn input_window(
    text: &str,
    cursor: usize,
    width: u16,
    height: u16,
) -> (Vec<String>, u16, u16) {
    let width = width.max(1) as usize;
    let height = height.max(1) as usize;
    let cursor = cursor.min(text.len());

    let mut rows: Vec<String> = vec![String::new()];
    let mut cursor_row = 0usize;
    let mut cursor_column = 0u16;
    let mut column = 0usize;
    let mut cursor_seen = cursor == 0;

    for (index, character) in text.char_indices() {
        if character == '\n' {
            rows.push(String::new());
            column = 0;
        } else {
            let char_width = character.width().unwrap_or(0);
            if column + char_width > width && column > 0 {
                rows.push(String::new());
                column = 0;
            }
            rows.last_mut().unwrap().push(character);
            column += char_width;
        }
        if index + character.len_utf8() == cursor {
            cursor_row = rows.len() - 1;
            cursor_column = column as u16;
            cursor_seen = true;
        }
    }
    if !cursor_seen {
        cursor_row = rows.len() - 1;
        cursor_column = column as u16;
    }

    // A cursor exactly at the right edge belongs at the start of the next
    // visual row, not on top of the last character.
    if cursor_column as usize >= width {
        cursor_column = 0;
        cursor_row += 1;
        if cursor_row >= rows.len() {
            rows.push(String::new());
        }
    }

    let start = cursor_row
        .saturating_sub(height.saturating_sub(1))
        .min(rows.len().saturating_sub(height));
    let visible: Vec<String> = rows.into_iter().skip(start).take(height).collect();
    (
        visible,
        (cursor_row - start) as u16,
        cursor_column.min(width as u16 - 1),
    )
}

/// A compact activity panel used by the Threads and Jobs tabs.
pub(crate) fn render_activity(frame: &mut Frame, area: Rect, app: &App, title: &str) {
    if area.height < 3 {
        return;
    }
    let block = bordered(title, false);
    let inner = block.inner(area);
    frame.render_widget(block, area);
    if app.activity.is_empty() || inner.height == 0 {
        return;
    }
    let take = inner.height as usize;
    let start = app.activity.len().saturating_sub(take);
    let lines: Vec<Line> = app
        .activity
        .iter()
        .skip(start)
        .map(|entry| {
            let time = model::fmt_clock(entry.at);
            Line::from(vec![
                Span::styled(format!("{time} "), Style::default().fg(FAINT)),
                Span::styled(
                    fit(&entry.text, inner.width.saturating_sub(10) as usize),
                    style_for(entry.level),
                ),
            ])
        })
        .collect();
    frame.render_widget(Paragraph::new(lines), inner);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::{App, Tab};
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    fn rendered(app: &App, width: u16, height: u16) -> String {
        let backend = TestBackend::new(width, height);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal.draw(|frame| draw(frame, app)).unwrap();
        terminal
            .backend()
            .buffer()
            .content
            .iter()
            .map(|cell| cell.symbol())
            .collect()
    }

    #[test]
    fn every_tab_and_overlay_draws_at_small_and_large_sizes() {
        let mut app = App::test_app();
        for (width, height) in [(46, 14), (80, 24), (120, 40), (190, 55)] {
            for tab in Tab::ALL {
                app.tab = tab;
                let text = rendered(&app, width, height);
                assert!(text.contains("HERMES") || width < 20);
            }
            app.tab = Tab::Threads;
            assert!(rendered(&app, width, height).contains("Tracked"));
            app.tab = Tab::Today;
            assert!(rendered(&app, width, height).contains("TODAY"));
            app.tab = Tab::Chat;
            assert!(rendered(&app, width, height).contains("CONVERSATION"));

            app.command.open = true;
            app.command
                .input
                .set("track https://example.test/archives/C1/p123");
            let _ = rendered(&app, width, height);
            app.command.open = false;

            app.choice = Some(crate::app::ChoiceState {
                title: "Snooze".to_string(),
                options: vec![("1h".to_string(), "in an hour".to_string())],
                selected: 0,
                action: crate::app::ChoiceAction::Snooze,
            });
            let _ = rendered(&app, width, height);
            app.choice = None;

            app.jump = Some(crate::app::JumpState::new(
                vec![crate::app::JumpEntry {
                    title: "dLocal SAML".to_string(),
                    meta: "aaa-internal · slack".to_string(),
                    kind: crate::app::JumpKind::Thread,
                    target: crate::app::JumpTarget::Thread("C1:1.0".to_string()),
                }],
                None,
            ));
            let _ = rendered(&app, width, height);
            app.jump = None;

            app.help = true;
            let _ = rendered(&app, width, height);
            app.help = false;
        }
    }

    #[test]
    fn tab_bar_names_all_four_tabs() {
        let app = App::test_app();
        let text = rendered(&app, 120, 40);
        assert!(text.contains("1 Chat"));
        assert!(text.contains("2 Today"));
        assert!(text.contains("3 Threads"));
        assert!(text.contains("4 Jobs"));
    }

    #[test]
    fn chat_screen_explains_how_to_start_a_thread() {
        let mut app = App::test_app();
        app.chat.begin_draft(None, None);
        let text = rendered(&app, 110, 34);
        assert!(text.contains("Type a message to start a new thread"));
        assert!(text.contains("Start a new thread"));
    }

    #[test]
    fn wraps_long_lines_and_preserves_newlines() {
        let lines = wrap_text("one two three four\n\nfive", 9);
        assert_eq!(lines, vec!["one two", "three", "four", "", "five"]);
    }

    #[test]
    fn hard_wraps_a_single_long_word() {
        let lines = wrap_text("abcdefghij", 4);
        assert_eq!(lines, vec!["abcd", "efgh", "ij"]);
    }

    #[test]
    fn fit_uses_display_width() {
        assert_eq!(fit("hello", 10), "hello");
        assert_eq!(fit("hello world", 7), "hello …");
        assert_eq!(fit("żółć", 3), "żó…");
    }

    #[test]
    fn input_window_tracks_the_cursor_across_wraps() {
        let (lines, row, column) = input_window("abcdef", 3, 4, 3);
        assert_eq!(lines, vec!["abcd", "ef"]);
        assert_eq!(row, 0);
        assert_eq!(column, 3);

        let (lines, row, column) = input_window("abcdef", 6, 4, 3);
        assert_eq!(lines, vec!["abcd", "ef"]);
        assert_eq!(row, 1);
        assert_eq!(column, 2);

        let (lines, row, column) = input_window("abcdef", 0, 4, 3);
        assert_eq!(lines, vec!["abcd", "ef"]);
        assert_eq!(row, 0);
        assert_eq!(column, 0);

        let (lines, row, column) = input_window("abcdef", 4, 4, 3);
        assert_eq!(lines, vec!["abcd", "ef"]);
        assert_eq!(row, 1);
        assert_eq!(column, 0);
    }

    #[test]
    fn bars_render_a_tenth_scale() {
        assert_eq!(bar(Some(50.0), 10), "█████░░░░░");
        assert_eq!(bar(None, 4), "░░░░");
    }
}
