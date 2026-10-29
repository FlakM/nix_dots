//! Threads tab: filter chips, the two-line thread list, detail card and activity.

use super::{
    bar, bordered, cadence_label, fit, kind_style, priority_style, render_activity, score_style,
    wrap_text, SELECT_FOCUS,
};
use crate::app::{App, Filter, ThreadsState};
use crate::model::{self, Entry, ThreadView};
use crate::theme::{self, *};
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, ListState, Paragraph};
use ratatui::Frame;
use unicode_width::UnicodeWidthStr;

pub fn draw(frame: &mut Frame, area: Rect, app: &App, state: &ThreadsState, today: bool) {
    let list_width = ((area.width as f32 * 0.46) as u16)
        .clamp(36, 72)
        .min(area.width.saturating_sub(32));
    let chunks = Layout::horizontal([Constraint::Length(list_width.max(28)), Constraint::Min(28)])
        .split(area);
    draw_list(frame, chunks[0], state, today);
    draw_right(frame, chunks[1], app, state);
}

fn draw_list(frame: &mut Frame, area: Rect, state: &ThreadsState, today: bool) {
    let threads = state;
    let mut title = if today {
        format!(
            "TODAY · {} active",
            if threads.loaded {
                threads.views.len().to_string()
            } else {
                "…".to_string()
            }
        )
    } else {
        format!(
            "THREADS · {} {}",
            threads.filter.label().to_uppercase(),
            if threads.loaded {
                threads.views.len().to_string()
            } else {
                "…".to_string()
            }
        )
    };
    if !threads.entries.is_empty() {
        title.push_str(&format!(
            " · {}/{}",
            threads.selected + 1,
            threads.entries.len()
        ));
    }
    let block = bordered(title, true);
    let inner = block.inner(area);
    frame.render_widget(block, area);
    if inner.height < 2 {
        return;
    }

    let filter_height = 1u16;
    let search_height = u16::from(!threads.search.is_empty());
    let chunks = Layout::vertical([
        Constraint::Length(filter_height),
        Constraint::Min(1),
        Constraint::Length(search_height),
    ])
    .split(inner);

    draw_filter_chips(frame, chunks[0], state, today);

    if threads.entries.is_empty() {
        draw_empty(frame, chunks[1], state, today);
        if search_height > 0 {
            draw_search_line(frame, chunks[2], state);
        }
        return;
    }

    let items: Vec<ListItem> = threads
        .entries
        .iter()
        .map(|entry| thread_item(entry, chunks[1].width, today))
        .collect();
    let list = List::new(items).highlight_style(Style::default().bg(SELECT_FOCUS));
    let mut list_state = ListState::default();
    list_state.select(Some(threads.selected.min(threads.entries.len() - 1)));
    frame.render_stateful_widget(list, chunks[1], &mut list_state);

    if search_height > 0 {
        draw_search_line(frame, chunks[2], state);
    }
}

fn draw_filter_chips(frame: &mut Frame, area: Rect, state: &ThreadsState, today: bool) {
    if today {
        let line = Line::from(vec![
            Span::styled(" ", theme::base()),
            Span::styled("since 00:00", Style::default().fg(AMBER)),
            Span::styled("  ·  work threads", theme::hint()),
            Span::styled("   ctrl+l jump", theme::hint()),
        ]);
        frame.render_widget(Paragraph::new(line), area);
        return;
    }
    let mut spans = Vec::new();
    spans.push(Span::styled(" ", theme::base()));
    for filter in Filter::ALL {
        let active = filter == state.filter;
        let style = if active {
            Style::default()
                .bg(SELECT_FOCUS)
                .fg(ACCENT)
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(HINT)
        };
        spans.push(Span::styled(if active { "▸ " } else { "  " }, style));
        spans.push(Span::styled(format!("{} ", filter.label()), style));
        spans.push(Span::raw(" "));
    }
    spans.push(Span::styled("[ ] switch", theme::hint()));
    frame.render_widget(Paragraph::new(Line::from(spans)), area);
}

fn thread_item(entry: &Entry, width: u16, today: bool) -> ListItem<'static> {
    let view = &entry.view;
    let available = width.saturating_sub(2) as usize;
    let mut head: Vec<Span> = Vec::new();
    head.push(Span::styled(
        "▌ ",
        Style::default().fg(if view.waiting { AMBER } else { BORDER }),
    ));
    if entry.indent {
        head.push(Span::styled("· ", theme::dim()));
    }
    head.push(Span::styled(
        format!("{:>2} ", view.priority_label),
        priority_style(view),
    ));
    if let Some(urgency) = view.urgency {
        head.push(Span::styled(
            format!("{:>3} ", urgency as i64),
            score_style(Some(urgency)),
        ));
    } else {
        head.push(Span::raw("    "));
    }
    if view.importance {
        head.push(Span::styled(
            "★ ",
            Style::default().fg(AMBER).add_modifier(Modifier::BOLD),
        ));
    } else {
        head.push(Span::raw("  "));
    }
    if view.waiting {
        head.push(Span::styled("⏳ ", Style::default().fg(AMBER)));
    }
    if entry.is_group() {
        head.push(Span::styled(
            if entry.expanded { "▾ " } else { "▸ " },
            Style::default().fg(BLUE).add_modifier(Modifier::BOLD),
        ));
    }
    let prefix_width: usize = head.iter().map(|span| span.content.width()).sum();
    let title = if view.headline.is_empty() {
        &view.summary
    } else {
        &view.headline
    };
    let suffix_width = if entry.is_group() {
        entry.count.to_string().len() + 3
    } else {
        0
    };
    head.push(Span::styled(
        fit(title, available.saturating_sub(prefix_width + suffix_width)),
        Style::default().fg(INK),
    ));
    if entry.is_group() && entry.count > 1 {
        head.push(Span::styled(
            format!(" ×{}", entry.count),
            Style::default().fg(BLUE).add_modifier(Modifier::BOLD),
        ));
    }

    let mut meta: Vec<Span> = vec![Span::styled("      ", theme::base())];
    if entry.is_group() {
        meta.push(Span::styled(
            format!("{} threads", entry.count),
            Style::default().fg(BLUE),
        ));
        meta.push(Span::styled("  ·  ", theme::dim()));
    }
    if !view.channel_name.is_empty() {
        meta.push(Span::styled(
            view.channel_name.clone(),
            Style::default().fg(BLUE),
        ));
        meta.push(Span::styled("  ·  ", theme::dim()));
    }
    meta.push(Span::styled(view.kind.clone(), kind_style(&view.kind)));
    meta.push(Span::styled("  ·  ", theme::dim()));
    meta.push(Span::styled(view.age.clone(), Style::default().fg(HINT)));
    meta.push(Span::styled("  ·  ", theme::dim()));
    meta.push(Span::styled(
        cadence_label(&view.cadence),
        Style::default().fg(HINT),
    ));
    if !today && !view.topic.is_empty() && !entry.is_group() {
        meta.push(Span::styled("  ·  ", theme::dim()));
        meta.push(Span::styled(fit(&view.topic, 18), theme::dim()));
    }
    if view.snoozed {
        meta.push(Span::styled("  ·  snoozed", theme::dim()));
    }
    if view.done {
        meta.push(Span::styled("  ·  done", Style::default().fg(ACCENT)));
    }

    ListItem::new(vec![Line::from(head), Line::from(meta)])
}

fn draw_search_line(frame: &mut Frame, area: Rect, state: &ThreadsState) {
    let line = Line::from(vec![
        Span::styled(" /", Style::default().fg(BLUE)),
        Span::styled(state.search.clone(), Style::default().fg(BLUE)),
        Span::styled("   esc clears", theme::hint()),
    ]);
    frame.render_widget(Paragraph::new(line), area);
}

fn draw_empty(frame: &mut Frame, area: Rect, state: &ThreadsState, today: bool) {
    let mut lines: Vec<Line> = Vec::new();
    if today {
        lines.push(Line::from(Span::styled(
            "Nothing active today yet.",
            Style::default().fg(INK).add_modifier(Modifier::BOLD),
        )));
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            "Threads with activity since 00:00 appear here automatically.",
            Style::default().fg(MUTED),
        )));
        lines.push(Line::from(vec![
            Span::styled("  ctrl+l ", theme::key()),
            Span::styled("jump to any conversation or thread", theme::hint()),
        ]));
        frame.render_widget(Paragraph::new(lines), area);
        return;
    }
    if !state.search.is_empty() {
        lines.push(Line::from(Span::styled(
            format!("Nothing matches {:?}.", state.search),
            Style::default().fg(INK).add_modifier(Modifier::BOLD),
        )));
        lines.push(Line::from(""));
        lines.push(Line::from(vec![
            Span::styled("esc ", theme::key()),
            Span::styled("clears the filter, or press ", theme::hint()),
            Span::styled("/", theme::key()),
            Span::styled(" for a new one", theme::hint()),
        ]));
    } else {
        lines.push(Line::from(Span::styled(
            "Nothing tracked here yet.",
            Style::default().fg(INK).add_modifier(Modifier::BOLD),
        )));
        lines.push(Line::from(""));
        match state.filter {
            Filter::Tracked => {
                lines.push(Line::from(Span::styled(
                    "Add what you actually care about:",
                    Style::default().fg(MUTED),
                )));
                lines.push(Line::from(vec![
                    Span::styled("  t  ", theme::key()),
                    Span::styled("track a Slack / PR / Jira link", theme::hint()),
                ]));
                lines.push(Line::from(vec![
                    Span::styled("  :  ", theme::key()),
                    Span::styled("command bar · :track <url>", theme::hint()),
                ]));
                lines.push(Line::from(vec![
                    Span::styled("  [ ]", theme::key()),
                    Span::styled(" look at followed / all threads", theme::hint()),
                ]));
                lines.push(Line::from(""));
                lines.push(Line::from(Span::styled(
                    "Auto-followed threads still notify you; they are just not tracked.",
                    Style::default().fg(FAINT),
                )));
            }
            Filter::Followed => {
                lines.push(Line::from(Span::styled(
                    "No auto-followed threads have activity.",
                    Style::default().fg(MUTED),
                )));
                lines.push(Line::from(vec![
                    Span::styled("  [ ]", theme::key()),
                    Span::styled(" switch to tracked or all", theme::hint()),
                ]));
            }
            Filter::All => {
                lines.push(Line::from(Span::styled(
                    "No threads are known to Hermes yet.",
                    Style::default().fg(MUTED),
                )));
            }
        }
    }
    frame.render_widget(Paragraph::new(lines), area);
}

fn draw_right(frame: &mut Frame, area: Rect, app: &App, state: &ThreadsState) {
    let chunks = Layout::vertical([
        Constraint::Percentage(52),
        Constraint::Length(2),
        Constraint::Min(5),
    ])
    .split(area);
    draw_detail(frame, chunks[0], state);
    draw_actions(frame, chunks[1], state);
    render_activity(frame, chunks[2], app, "ACTIVITY");
}

fn draw_detail(frame: &mut Frame, area: Rect, state: &ThreadsState) {
    let block = bordered("DETAIL", false);
    let inner = block.inner(area);
    frame.render_widget(block, area);
    let Some(entry) = state.selected_entry() else {
        let line = Line::from(Span::styled(
            "Select a thread to see its detail, or press ? for the key map.",
            Style::default().fg(MUTED),
        ));
        frame.render_widget(Paragraph::new(line), inner);
        return;
    };
    let lines = detail_lines(entry, inner.width.saturating_sub(2) as usize);
    let offset =
        (state.detail_scroll as usize).min(lines.len().saturating_sub(inner.height as usize));
    frame.render_widget(Paragraph::new(lines).scroll((offset as u16, 0)), inner);
}

fn detail_lines(entry: &Entry, width: usize) -> Vec<Line<'static>> {
    let view: &ThreadView = &entry.view;
    let mut lines: Vec<Line<'static>> = Vec::new();

    let mut badges: Vec<Span> = Vec::new();
    if view.waiting {
        badges.push(Span::styled(
            "WAITING ON YOU",
            Style::default().fg(AMBER).add_modifier(Modifier::BOLD),
        ));
        badges.push(Span::raw("   "));
    }
    if view.importance {
        badges.push(Span::styled(
            "★ important",
            Style::default().fg(AMBER).add_modifier(Modifier::BOLD),
        ));
        badges.push(Span::raw("   "));
    }
    badges.push(Span::styled(
        if view.status.is_empty() {
            "open".to_string()
        } else {
            view.status.clone()
        },
        Style::default().fg(MUTED),
    ));
    if view.done {
        badges.push(Span::styled("  · done", Style::default().fg(ACCENT)));
    }
    lines.push(Line::from(badges));
    lines.push(Line::from(""));

    if entry.is_group() {
        lines.push(Line::from(Span::styled(
            format!("{} threads · topic {}", entry.count, entry.topic),
            Style::default().fg(BLUE).add_modifier(Modifier::BOLD),
        )));
    }
    let title = if view.headline.is_empty() {
        &view.summary
    } else {
        &view.headline
    };
    for chunk in wrap_text(title, width) {
        lines.push(Line::from(Span::styled(
            chunk,
            Style::default().fg(INK).add_modifier(Modifier::BOLD),
        )));
    }
    lines.push(Line::from(""));

    let meta = [
        (
            "priority",
            view.priority_label.clone(),
            priority_style(view),
        ),
        (
            "channel",
            view.channel_name.clone(),
            Style::default().fg(BLUE),
        ),
        ("kind", view.kind.clone(), kind_style(&view.kind)),
        ("idle", view.age.clone(), Style::default().fg(MUTED)),
        (
            "cadence",
            if view.cadence == "off" {
                "no reminders".to_string()
            } else if view.cadence.is_empty() || view.cadence == "-" {
                "activity".to_string()
            } else {
                view.cadence.clone()
            },
            Style::default().fg(MUTED),
        ),
    ];
    for chunk in meta.chunks(2) {
        let mut spans = Vec::new();
        for (label, value, style) in chunk {
            spans.push(Span::styled(format!("{label:<10}"), theme::hint()));
            spans.push(Span::styled(format!("{:<22}", fit(value, 20)), *style));
        }
        lines.push(Line::from(spans));
    }

    if view.urgency.is_some() || view.relevance.is_some() {
        lines.push(Line::from(""));
        for (label, value, style) in [
            ("urgency", view.urgency, score_style(view.urgency)),
            ("relevance", view.relevance, Style::default().fg(BLUE)),
        ] {
            if value.is_none() {
                continue;
            }
            lines.push(Line::from(vec![
                Span::styled(format!("{label:<10}"), theme::hint()),
                Span::styled(bar(value, 10), style),
                Span::styled(format!(" {:>3}", value.unwrap_or(0.0) as i64), style),
            ]));
        }
    }
    if !view.closed_reason.is_empty() {
        let stamp = view
            .closed_at
            .map(|stamp| format!(" · {}", model::fmt_epoch(Some(stamp))))
            .unwrap_or_default();
        lines.push(Line::from(vec![
            Span::styled("closed   ", theme::hint()),
            Span::styled(
                format!("{}{stamp}", view.closed_reason),
                Style::default().fg(AMBER),
            ),
        ]));
    }
    if !view.note.is_empty() {
        lines.push(Line::from(vec![
            Span::styled("note     ", theme::hint()),
            Span::styled(
                fit(&view.note, width.saturating_sub(9)),
                Style::default().fg(INK),
            ),
        ]));
    }
    if !view.link.is_empty() {
        lines.push(Line::from(vec![
            Span::styled("link     ", theme::hint()),
            Span::styled(
                fit(&view.link, width.saturating_sub(9)),
                Style::default().fg(BLUE),
            ),
        ]));
    }
    lines
}

fn draw_actions(frame: &mut Frame, area: Rect, state: &ThreadsState) {
    let mut spans = Vec::new();
    let Some(entry) = state.selected_entry() else {
        frame.render_widget(Paragraph::new(Line::from("")), area);
        return;
    };
    let actions: &[(&str, &str)] = if entry.is_group() {
        &[("space", "expand"), ("enter", "open first"), ("a", "ask")]
    } else {
        &[
            ("o", "open"),
            ("a", "ask"),
            ("R", "remind"),
            ("s", "snooze"),
            ("d", "done"),
            ("i", "important"),
            ("f", "follow"),
            ("y", "copy"),
        ]
    };
    let width = area.width.saturating_sub(2) as usize;
    let mut line_width = 0usize;
    for (keys, label) in actions {
        let chunk_width = keys.len() + label.len() + 3;
        if line_width + chunk_width > width && line_width > 0 {
            break;
        }
        spans.push(Span::styled(format!(" {keys} "), theme::key()));
        spans.push(Span::styled(format!("{label}  "), theme::hint()));
        line_width += chunk_width;
    }
    frame.render_widget(Paragraph::new(Line::from(spans)), area);
}
