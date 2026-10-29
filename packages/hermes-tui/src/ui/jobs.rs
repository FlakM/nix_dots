//! Jobs tab: agent jobs, their steps, and the live event feed.

use super::{bordered, fit, render_activity, spinner, wrap_text, SELECT_FOCUS};
use crate::app::{App, JobSummary};
use crate::model;
use crate::theme::{self, *};
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, ListState, Paragraph};
use ratatui::Frame;

pub fn draw(frame: &mut Frame, area: Rect, app: &App) {
    let chunks = Layout::vertical([Constraint::Min(8), Constraint::Length(9)]).split(area);
    let top = Layout::horizontal([Constraint::Percentage(42), Constraint::Percentage(58)])
        .split(chunks[0]);
    draw_jobs(frame, top[0], app);
    draw_steps(frame, top[1], app);
    render_activity(frame, chunks[1], app, "EVENTS");
}

fn draw_jobs(frame: &mut Frame, area: Rect, app: &App) {
    let block = bordered(format!("JOBS · {}", app.jobs.jobs.len()), true);
    let inner = block.inner(area);
    frame.render_widget(block, area);
    if app.jobs.jobs.is_empty() {
        let lines = vec![
            Line::from(Span::styled(
                if app.jobs.loading {
                    "Loading jobs…"
                } else {
                    "No agent jobs yet."
                },
                Style::default().fg(MUTED),
            )),
            Line::from(""),
            Line::from(Span::styled(
                "Ask in Chat, or run :remote <command>.",
                theme::hint(),
            )),
        ];
        frame.render_widget(Paragraph::new(lines), inner);
        return;
    }

    let items: Vec<ListItem> = app
        .jobs
        .jobs
        .iter()
        .map(|job| job_item(job, inner.width))
        .collect();
    let list = List::new(items).highlight_style(Style::default().bg(SELECT_FOCUS));
    let mut state = ListState::default();
    state.select(Some(app.jobs.selected.min(app.jobs.jobs.len() - 1)));
    frame.render_stateful_widget(list, inner, &mut state);
}

fn job_item(job: &JobSummary, width: u16) -> ListItem<'static> {
    let (symbol, style) = match job.status.as_str() {
        "running" | "queued" | "pending" => ("◌", Style::default().fg(BLUE)),
        "done" | "ok" | "finished" | "completed" | "complete" => ("●", Style::default().fg(ACCENT)),
        "error" | "failed" | "cancelled" | "canceled" => ("✗", Style::default().fg(RED)),
        _ => ("○", Style::default().fg(MUTED)),
    };
    let status = if matches!(job.status.as_str(), "running" | "queued" | "pending") {
        "running".to_string()
    } else {
        job.status.clone()
    };
    let first = Line::from(vec![
        Span::styled(format!(" {symbol} "), style),
        Span::styled(
            fit(&job.title, width.saturating_sub(4) as usize),
            Style::default().fg(INK),
        ),
    ]);
    let second = Line::from(vec![
        Span::styled("   ", theme::base()),
        Span::styled(
            fit(
                &format!("{} · {status}", display_id(&job.id)),
                width.saturating_sub(6) as usize,
            ),
            theme::hint(),
        ),
    ]);
    ListItem::new(vec![first, second])
}

fn display_id(id: &str) -> String {
    if id.is_empty() {
        "?".to_string()
    } else {
        id.to_string()
    }
}

fn draw_steps(frame: &mut Frame, area: Rect, app: &App) {
    let Some(job) = app.jobs.selected() else {
        let block = bordered("JOB", false);
        let inner = block.inner(area);
        frame.render_widget(block, area);
        let lines = vec![
            Line::from(Span::styled(
                "Select a job to see its steps.",
                Style::default().fg(MUTED),
            )),
            Line::from(""),
            Line::from(Span::styled(
                "Chat answers and :remote commands stream steps here.",
                theme::hint(),
            )),
        ];
        frame.render_widget(Paragraph::new(lines), inner);
        return;
    };
    let block = bordered(
        format!("JOB {}", display_id(&job.id)),
        matches!(job.status.as_str(), "running" | "queued" | "pending"),
    );
    let inner = block.inner(area);
    frame.render_widget(block, area);

    let raw = &job.raw;
    let mut lines: Vec<Line> = Vec::new();
    let status_style = match job.status.as_str() {
        "error" | "failed" | "cancelled" | "canceled" => Style::default().fg(RED),
        "done" | "ok" | "finished" | "completed" => Style::default().fg(ACCENT),
        _ => Style::default().fg(BLUE),
    };
    lines.push(Line::from(vec![
        Span::styled("status   ", theme::hint()),
        Span::styled(
            job.status.clone(),
            status_style.add_modifier(Modifier::BOLD),
        ),
        if matches!(job.status.as_str(), "running" | "queued" | "pending") {
            Span::styled(
                format!("  {} working", spinner(app.spinner)),
                Style::default().fg(AMBER),
            )
        } else {
            Span::raw("")
        },
    ]));
    let question = model::job_title(raw);
    for chunk in wrap_text(&question, inner.width.saturating_sub(11) as usize) {
        lines.push(Line::from(vec![
            Span::styled("question ", theme::hint()),
            Span::styled(chunk, Style::default().fg(INK)),
        ]));
    }
    lines.push(Line::from(""));

    let steps = model::job_steps(raw);
    if steps.is_empty() {
        lines.push(Line::from(Span::styled(
            if matches!(job.status.as_str(), "running" | "queued" | "pending") {
                "Waiting for the first step…"
            } else {
                "No steps recorded."
            },
            theme::hint(),
        )));
    } else {
        for (index, step) in steps.iter().enumerate() {
            let (icon, style) = match step.status.to_lowercase().as_str() {
                "error" | "failed" => ("✗", Style::default().fg(RED)),
                "running" | "pending" => ("◌", Style::default().fg(BLUE)),
                _ => ("✓", Style::default().fg(ACCENT)),
            };
            lines.push(Line::from(vec![
                Span::styled(format!("{:>3} ", index + 1), theme::hint()),
                Span::styled(format!("{icon} "), style),
                Span::styled(
                    fit(&step.line(), inner.width.saturating_sub(9) as usize),
                    Style::default().fg(HINT),
                ),
            ]));
        }
    }

    let result = model::job_result(raw);
    let error = model::job_error(raw);
    if !result.is_empty() {
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            "result",
            Style::default().fg(ACCENT).add_modifier(Modifier::BOLD),
        )));
        for chunk in wrap_text(&result, inner.width.saturating_sub(2) as usize) {
            lines.push(Line::from(Span::styled(chunk, Style::default().fg(INK))));
        }
    }
    if !error.is_empty() {
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            "error",
            Style::default().fg(RED).add_modifier(Modifier::BOLD),
        )));
        for chunk in wrap_text(&error, inner.width.saturating_sub(2) as usize) {
            lines.push(Line::from(Span::styled(chunk, Style::default().fg(RED))));
        }
    }

    let offset = lines.len().saturating_sub(inner.height as usize);
    frame.render_widget(
        Paragraph::new(lines).scroll((offset.min(u16::MAX as usize) as u16, 0)),
        inner,
    );
}
