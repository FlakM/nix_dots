//! Chat tab: conversation list, transcript and composer.

use super::{bordered, fit, input_window, spinner, wrap_text, SELECT, SELECT_FOCUS};
use crate::app::{App, ChatFocus};
use crate::chat::{Conversation, Role};
use crate::model;
use crate::theme::{self, *};
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, List, ListItem, ListState, Paragraph};
use ratatui::Frame;

pub fn draw(frame: &mut Frame, area: Rect, app: &App) {
    let list_width = ((area.width as f32 * 0.30) as u16).clamp(24, 42);
    let list_width = list_width.min(area.width.saturating_sub(24)).max(18);
    let chunks =
        Layout::horizontal([Constraint::Length(list_width), Constraint::Min(20)]).split(area);
    draw_list(frame, chunks[0], app);
    draw_conversation(frame, chunks[1], app);
}

fn draw_list(frame: &mut Frame, area: Rect, app: &App) {
    let focused = app.chat.focus == ChatFocus::List;
    let count = app.chat.store.conversations.len();
    let title = if count == 0 {
        "THREADS".to_string()
    } else if app.chat.selected == 0 {
        format!("THREADS · new · {count}")
    } else {
        format!("THREADS · {}/{count}", app.chat.selected)
    };
    let block = bordered(title, focused);
    let mut items: Vec<ListItem> = Vec::new();

    let draft_active = app.chat.draft.is_some();
    let draft_title = app
        .chat
        .draft
        .as_ref()
        .map(|draft| draft.title_or_placeholder().to_string());
    let (new_title, new_meta) = match draft_title.as_deref() {
        Some("New thread") | None if draft_active => (
            "＋ New thread · typing".to_string(),
            "first message names it",
        ),
        Some(title) => (format!("＋ {title}"), "about the selection · type below"),
        None => ("＋ New thread".to_string(), "start a conversation · n"),
    };
    items.push(ListItem::new(vec![
        Line::from(vec![
            Span::styled("▌ ", Style::default().fg(AMBER)),
            Span::styled(
                fit(&new_title, area.width.saturating_sub(5) as usize),
                Style::default().fg(ACCENT).add_modifier(Modifier::BOLD),
            ),
        ]),
        Line::from(vec![
            Span::styled("  ", theme::base()),
            Span::styled(new_meta, theme::dim()),
        ]),
    ]));

    for conversation in &app.chat.store.conversations {
        let pending = conversation.is_pending();
        let spinner_text = if pending {
            format!("{} ", spinner(app.spinner))
        } else {
            String::new()
        };
        let title = conversation.title_or_placeholder().to_string();
        let mut first = vec![Span::styled(
            if conversation.is_empty() {
                "· "
            } else {
                "▌ "
            },
            Style::default().fg(if pending { AMBER } else { BLUE }),
        )];
        if pending {
            first.push(Span::styled(spinner_text, Style::default().fg(AMBER)));
        }
        let title_width = area.width.saturating_sub(6 + if pending { 2 } else { 0 }) as usize;
        first.push(Span::styled(
            fit(&title, title_width),
            Style::default().fg(INK),
        ));
        let mut second = vec![Span::styled(
            format!(
                "  {}",
                model::fmt_duration(Some(age(conversation.updated_at)))
            ),
            theme::hint(),
        )];
        second.push(Span::styled(
            format!(" · {} msgs", conversation.message_count()),
            theme::hint(),
        ));
        if let Some(key) = &conversation.thread_key {
            second.push(Span::styled(
                format!(" · {}", fit(key, 14)),
                Style::default().fg(BLUE),
            ));
        }
        if pending {
            second.push(Span::styled(" · working", Style::default().fg(AMBER)));
        }
        items.push(ListItem::new(vec![Line::from(first), Line::from(second)]));
    }

    let highlight = if focused {
        Style::default().bg(SELECT_FOCUS)
    } else {
        Style::default().bg(SELECT)
    };
    let list = List::new(items).block(block).highlight_style(highlight);
    let mut state = ListState::default();
    state.select(Some(
        app.chat
            .selected
            .min(app.chat.row_count().saturating_sub(1)),
    ));
    frame.render_stateful_widget(list, area, &mut state);
}

fn age(updated_at: i64) -> f64 {
    let now = chrono::Local::now().timestamp();
    (now - updated_at).max(0) as f64
}

fn draw_conversation(frame: &mut Frame, area: Rect, app: &App) {
    let chunks = Layout::vertical([
        Constraint::Length(1),
        Constraint::Min(4),
        Constraint::Length(4),
    ])
    .split(area);

    let conversation = app.chat.selected_conversation();
    draw_header(frame, chunks[0], app, conversation);
    draw_transcript(frame, chunks[1], app, conversation);
    draw_composer(frame, chunks[2], app, conversation);
}

fn draw_header(frame: &mut Frame, area: Rect, app: &App, conversation: Option<&Conversation>) {
    frame.render_widget(Block::default().style(theme::panel()), area);
    let mut spans = Vec::new();
    match conversation {
        Some(conversation) => {
            let key_width = conversation
                .thread_key
                .as_ref()
                .map(|_| "  about ".len() + 18)
                .unwrap_or(0);
            let pending_width = if conversation.is_pending() { 12 } else { 0 };
            let title_width = area
                .width
                .saturating_sub((5 + key_width + pending_width) as u16)
                as usize;
            spans.push(Span::styled(" ", theme::panel()));
            spans.push(Span::styled(
                "▌ ",
                Style::default().fg(if conversation.is_pending() {
                    AMBER
                } else {
                    ACCENT
                }),
            ));
            spans.push(Span::styled(
                fit(conversation.title_or_placeholder(), title_width),
                Style::default().fg(INK).add_modifier(Modifier::BOLD),
            ));
            if let Some(key) = &conversation.thread_key {
                spans.push(Span::styled("  about ", theme::hint()));
                spans.push(Span::styled(fit(key, 18), Style::default().fg(BLUE)));
            }
            if conversation.is_pending() {
                spans.push(Span::styled(
                    format!("   {} working", spinner(app.spinner)),
                    Style::default().fg(AMBER),
                ));
            }
        }
        None => {
            spans.push(Span::styled(" ", theme::panel()));
            spans.push(Span::styled(
                "New thread",
                Style::default().fg(ACCENT).add_modifier(Modifier::BOLD),
            ));
            spans.push(Span::styled(
                "   type a message below and press Enter",
                theme::hint(),
            ));
        }
    }
    frame.render_widget(
        Paragraph::new(Line::from(spans)).style(theme::panel()),
        area,
    );
}

fn draw_transcript(frame: &mut Frame, area: Rect, app: &App, conversation: Option<&Conversation>) {
    let title = if conversation
        .map(|conversation| conversation.is_pending())
        .unwrap_or(false)
    {
        format!("CONVERSATION · {}", spinner(app.spinner))
    } else {
        "CONVERSATION".to_string()
    };
    let block = bordered(title, app.chat.focus == ChatFocus::Composer);
    let inner = block.inner(area);
    frame.render_widget(block, area);

    let width = inner.width.saturating_sub(4) as usize;
    let lines = transcript_lines(app, conversation, width);
    let offset = if app.chat.follow {
        lines.len().saturating_sub(inner.height as usize)
    } else {
        (app.chat.scroll as usize).min(lines.len().saturating_sub(inner.height as usize))
    };
    let paragraph = Paragraph::new(lines).scroll((offset.min(u16::MAX as usize) as u16, 0));
    frame.render_widget(paragraph, inner);
}

fn transcript_lines(
    app: &App,
    conversation: Option<&Conversation>,
    width: usize,
) -> Vec<Line<'static>> {
    let Some(conversation) = conversation else {
        return empty_hints(width, false);
    };
    if conversation.messages.is_empty() {
        return empty_hints(width, conversation.thread_key.is_some());
    }

    let mut lines: Vec<Line<'static>> = Vec::new();
    for message in &conversation.messages {
        match message.role {
            Role::Step => {
                for (index, chunk) in wrap_text(&message.text, width.saturating_sub(4))
                    .iter()
                    .enumerate()
                {
                    let prefix = if index == 0 { "  ✓ " } else { "    " };
                    lines.push(Line::from(vec![
                        Span::styled(prefix, Style::default().fg(FAINT)),
                        Span::styled(chunk.clone(), theme::dim()),
                    ]));
                }
            }
            Role::Error => {
                lines.push(Line::from(vec![
                    Span::styled("  ✗ ", Style::default().fg(RED)),
                    Span::styled(
                        format!("ERROR · {}", model::fmt_clock(message.ts)),
                        Style::default().fg(RED).add_modifier(Modifier::BOLD),
                    ),
                ]));
                for chunk in wrap_text(&message.text, width.saturating_sub(4)) {
                    lines.push(Line::from(vec![
                        Span::styled("    ", theme::base()),
                        Span::styled(chunk, Style::default().fg(RED)),
                    ]));
                }
                lines.push(Line::from(""));
            }
            Role::User | Role::Assistant => {
                let (label, color) = match message.role {
                    Role::User => ("YOU", BLUE),
                    _ => ("HERMES", ACCENT),
                };
                lines.push(Line::from(vec![
                    Span::styled("  ▌ ", Style::default().fg(color)),
                    Span::styled(
                        format!("{label} · {}", model::fmt_clock(message.ts)),
                        Style::default().fg(color).add_modifier(Modifier::BOLD),
                    ),
                ]));
                for chunk in wrap_text(&message.text, width.saturating_sub(4)) {
                    lines.push(Line::from(vec![
                        Span::styled("    ", theme::base()),
                        Span::styled(chunk, Style::default().fg(INK)),
                    ]));
                }
                lines.push(Line::from(""));
            }
        }
    }
    if conversation.is_pending() {
        lines.push(Line::from(vec![
            Span::styled("  ", theme::base()),
            Span::styled(
                format!(
                    "{} Hermes is thinking…  (Ctrl+X cancels)",
                    spinner(app.spinner)
                ),
                Style::default().fg(AMBER),
            ),
        ]));
    }
    if lines.is_empty() {
        lines.push(Line::from(""));
    }
    lines
}

fn empty_hints(width: usize, about_thread: bool) -> Vec<Line<'static>> {
    let mut lines = Vec::new();
    let heading = if about_thread {
        "Ask about this thread"
    } else {
        "Start a new thread"
    };
    lines.push(Line::from(Span::styled(
        heading,
        Style::default().fg(ACCENT).add_modifier(Modifier::BOLD),
    )));
    lines.push(Line::from(""));
    let intro = if about_thread {
        "The selected thread is attached as context. Ask a question, or use investigate / draft."
    } else {
        "Type a message below and press Enter. Hermes answers here; follow-ups keep the context of this conversation."
    };
    for chunk in wrap_text(intro, width) {
        lines.push(Line::from(Span::styled(chunk, Style::default().fg(HINT))));
    }
    lines.push(Line::from(""));
    lines.push(Line::from(Span::styled("Try", theme::hint())));
    let examples = if about_thread {
        vec![
            "what changed here?",
            "what is waiting on me?",
            "draft a reply",
        ]
    } else {
        vec![
            "what is waiting on me?",
            "summarise the dLocal SAML thread",
            "draft a reply to the auth incident",
        ]
    };
    for example in examples {
        lines.push(Line::from(vec![
            Span::styled("  ❯ ", Style::default().fg(ACCENT)),
            Span::styled(example.to_string(), Style::default().fg(INK)),
        ]));
    }
    lines.push(Line::from(""));
    lines.push(Line::from(vec![
        Span::styled("  Enter ", theme::key()),
        Span::styled("sends · ", theme::hint()),
        Span::styled("Ctrl+N ", theme::key()),
        Span::styled("starts another thread · ", theme::hint()),
        Span::styled("Esc ", theme::key()),
        Span::styled("browses history", theme::hint()),
    ]));
    lines
}

fn draw_composer(frame: &mut Frame, area: Rect, app: &App, conversation: Option<&Conversation>) {
    let focused = app.chat.focus == ChatFocus::Composer;
    let pending = conversation
        .map(|conversation| conversation.is_pending())
        .unwrap_or(false);
    let title = if pending {
        "Message · Hermes is working · Ctrl+X cancels".to_string()
    } else if focused {
        "Message · Enter sends · Shift+Enter newline · Esc history".to_string()
    } else {
        "Message · press Enter or i to write".to_string()
    };
    let block = Block::default()
        .borders(ratatui::widgets::Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(if focused { ACCENT } else { BORDER }))
        .title(Span::styled(
            format!(" {title} "),
            Style::default()
                .fg(if focused { ACCENT } else { MUTED })
                .add_modifier(Modifier::BOLD),
        ))
        .style(theme::base());
    let inner = block.inner(area);
    frame.render_widget(block, area);

    let placeholder = if pending {
        "waiting for the answer…"
    } else if conversation
        .map(|conversation| conversation.is_empty())
        .unwrap_or(true)
    {
        "Type a message to start a new thread…"
    } else {
        "Ask a follow-up…"
    };

    if app.chat.input.is_empty() {
        let line = Line::from(vec![
            Span::styled(" ", theme::base()),
            Span::styled(placeholder, Style::default().fg(FAINT)),
        ]);
        frame.render_widget(Paragraph::new(line), inner);
        if focused {
            let x = (inner.x + 1).min(inner.x + inner.width.saturating_sub(1));
            frame.set_cursor_position((x, inner.y));
        }
        return;
    }

    let (rows, cursor_row, cursor_column) = input_window(
        &app.chat.input.text,
        app.chat.input.cursor,
        inner.width.saturating_sub(1),
        inner.height,
    );
    let lines: Vec<Line> = rows
        .into_iter()
        .map(|row| {
            Line::from(vec![
                Span::styled(" ", theme::base()),
                Span::styled(row, Style::default().fg(INK)),
            ])
        })
        .collect();
    frame.render_widget(Paragraph::new(lines), inner);
    if focused {
        let x = (inner.x + 1 + cursor_column).min(inner.x + inner.width.saturating_sub(1));
        let y = (inner.y + cursor_row).min(inner.y + inner.height.saturating_sub(1));
        frame.set_cursor_position((x, y));
    }
}
