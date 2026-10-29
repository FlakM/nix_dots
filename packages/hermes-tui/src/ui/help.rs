//! The `?` overlay.

use super::{centered, wrap_text};
use crate::app::App;
use crate::theme::{self, *};
use ratatui::layout::Rect;
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Clear, Paragraph};
use ratatui::Frame;

pub fn draw_help(frame: &mut Frame, area: Rect, app: &App) {
    let popup = centered(
        area,
        area.width.saturating_sub(6).min(102),
        area.height.saturating_sub(4),
    );
    frame.render_widget(Clear, popup);
    let block = Block::default()
        .borders(ratatui::widgets::Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(ACCENT))
        .title(Span::styled(
            " Hermes help ",
            Style::default().fg(ACCENT).add_modifier(Modifier::BOLD),
        ))
        .style(theme::base());
    let inner = block.inner(popup);
    frame.render_widget(block, popup);

    let lines = help_lines(app, inner.width.saturating_sub(2) as usize);
    let offset = (app.help_scroll as usize).min(lines.len().saturating_sub(inner.height as usize));
    frame.render_widget(
        Paragraph::new(lines).scroll((offset.min(u16::MAX as usize) as u16, 0)),
        inner,
    );
}

fn help_lines(app: &App, width: usize) -> Vec<Line<'static>> {
    let mut lines = Vec::new();
    let mut push_section = |title: &str, rows: &[(&str, &str)]| {
        lines.push(Line::from(Span::styled(
            title.to_string(),
            Style::default().fg(ACCENT).add_modifier(Modifier::BOLD),
        )));
        for (keys, description) in rows {
            lines.push(Line::from(vec![
                Span::styled(format!("  {keys:<24}"), Style::default().fg(BLUE)),
                Span::styled(description.to_string(), Style::default().fg(HINT)),
            ]));
        }
        lines.push(Line::from(""));
    };

    push_section(
        "GETTING AROUND",
        &[
            (
                "1 / 2 / 3 / 4",
                "Chat, Today, Threads, Jobs (always visible)",
            ),
            ("tab / shift+tab", "next / previous tab"),
            (":", "command bar (same words as the Slack control surface)"),
            ("?  /  F1", "this help (F1 works while typing)"),
            ("q", "quit from a list"),
        ],
    );

    push_section(
        "JUMPING — HERDR / TMUX STYLE",
        &[
            ("ctrl+l", "jump to any conversation or tracked thread"),
            ("ctrl+b", "prefix (works from anywhere, even while typing)"),
            ("prefix + a / A", "next / previous thread instance"),
            ("prefix + j / k", "next / previous instance (same)"),
            ("prefix + g", "the jump picker"),
            ("prefix + 1..4", "Chat / Today / Threads / Jobs"),
            ("prefix + h / l", "previous / next tab"),
            ("prefix + c", "start a new chat thread"),
            ("prefix + esc", "cancel the prefix"),
        ],
    );

    push_section(
        "CHAT — TALK TO HERMES",
        &[
            ("n  /  ctrl+n", "start a new thread from anywhere"),
            ("enter", "send the message"),
            ("shift+enter / ctrl+j", "add a newline"),
            ("esc", "leave the composer, browse threads"),
            ("j / k", "move through past threads"),
            ("x", "delete the selected thread (local)"),
            ("ctrl+x", "cancel the running answer"),
            (":ask <question>", "start a thread and send immediately"),
            (
                ":investigate / :draft",
                "chat about the thread selected in Threads",
            ),
        ],
    );

    push_section(
        "THREADS — TRACKED SLACK / PR / JIRA",
        &[
            ("j / k, g / G", "move, first / last"),
            ("[ / ]", "switch the filter chips: Tracked, Followed, All"),
            ("/", "filter the list (esc clears it)"),
            ("t  /  :track <url>", "track a Slack / PR / Jira link"),
            ("a", "open a new Chat thread about the selection"),
            ("enter / o", "open the link (a group row expands)"),
            ("y", "copy the link"),
            ("space", "expand or collapse a topic group"),
            ("d / i / f", "done / important / follow"),
            ("s / R", "snooze / reminder cadence"),
            ("r", "refresh now"),
        ],
    );

    push_section(
        "TODAY — ACTIVITY SINCE LOCAL MIDNIGHT",
        &[
            ("tab 2 / ctrl+b, 2", "open Today"),
            ("j / k, enter", "move, open detail / link"),
            ("a / d / i / s", "ask / done / important / snooze"),
            ("/", "filter today's list"),
            ("ctrl+l", "jump anywhere"),
        ],
    );

    push_section(
        "JOBS — AGENT RUNS",
        &[
            ("j / k", "move through jobs"),
            ("c", "cancel the selected running job"),
            ("r", "refresh"),
            (
                "events",
                "notifications, job steps and thread updates stream below",
            ),
        ],
    );

    push_section(
        "COMMANDS",
        &[
            ("track <url> [every 1d]", "track a Slack / PR / Jira link"),
            ("untrack [key]", "stop tracking (defaults to the selection)"),
            ("remind 6h | off", "per-thread reminder cadence"),
            ("reminders 1d | off", "global default cadence"),
            ("task <text>", "natural-language Vikunja task"),
            ("notify <text>", "desktop notification on this machine"),
            ("ask <question>", "new Chat thread with an answer"),
            ("snooze 2h | off", "silence reminders for the selection"),
            ("done | important", "act on the selected thread"),
            ("follow | unfollow", "follow or unfollow the selection"),
            ("search <text>", "filter the thread list"),
            ("history [n]", "recent jobs"),
            ("remote <command>", "offload a build/test to amd-pc"),
            ("status", "health, counts and default cadence"),
            ("new | chat", "start a new conversation thread"),
        ],
    );

    if let Some(error) = &app.config_error {
        lines.push(Line::from(Span::styled(
            "CONFIGURATION",
            Style::default().fg(RED).add_modifier(Modifier::BOLD),
        )));
        for chunk in wrap_text(
            &format!(
                "No API client: {error}. Write ~/.config/hermes/client.env with \
                 HERMES_API_URL and HERMES_API_TOKEN_FILE, then restart hermes-tui."
            ),
            width,
        ) {
            lines.push(Line::from(Span::styled(chunk, Style::default().fg(RED))));
        }
        lines.push(Line::from(""));
    }

    lines.push(Line::from(vec![
        Span::styled(
            "esc / ? / F1",
            Style::default().fg(ACCENT).add_modifier(Modifier::BOLD),
        ),
        Span::styled("  close this help · ", theme::hint()),
        Span::styled("j / k", Style::default().fg(BLUE)),
        Span::styled(" scroll", theme::hint()),
    ]));
    lines
}
