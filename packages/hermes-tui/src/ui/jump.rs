//! The `ctrl+l` jump picker: type to filter conversations and work threads.

use super::{centered, fit};
use crate::app::{JumpKind, JumpState};
use crate::theme::{self, *};
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Clear, List, ListItem, ListState, Paragraph};
use ratatui::Frame;

pub fn draw(frame: &mut Frame, area: Rect, jump: &JumpState) {
    let popup = centered(
        area,
        area.width.saturating_sub(6).min(110),
        area.height.saturating_sub(4).min(30),
    );
    frame.render_widget(Clear, popup);
    let block = Block::default()
        .borders(ratatui::widgets::Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(ACCENT))
        .title(Span::styled(
            format!(
                " Jump to thread · {}/{} ",
                jump.filtered.len(),
                jump.all.len()
            ),
            Style::default().fg(ACCENT).add_modifier(Modifier::BOLD),
        ))
        .style(theme::base());
    let inner = block.inner(popup);
    frame.render_widget(block, popup);
    if inner.height < 3 {
        return;
    }

    let chunks = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(1),
        Constraint::Min(1),
        Constraint::Length(1),
    ])
    .split(inner);

    let query = Line::from(vec![
        Span::styled("❯ ", theme::key()),
        Span::styled(jump.query.text.clone(), Style::default().fg(INK)),
        Span::styled(
            if jump.query.text.is_empty() {
                "  type to filter conversations and threads"
            } else {
                ""
            },
            theme::hint(),
        ),
    ]);
    frame.render_widget(Paragraph::new(query), chunks[0]);
    let cursor = jump.query.text[..jump.query.cursor.min(jump.query.text.len())]
        .chars()
        .count() as u16;
    frame.set_cursor_position((
        (chunks[0].x + 2 + cursor).min(chunks[0].x + chunks[0].width.saturating_sub(1)),
        chunks[0].y,
    ));
    frame.render_widget(
        Paragraph::new(Line::from(Span::styled(
            "─".repeat(chunks[1].width as usize),
            Style::default().fg(BORDER),
        ))),
        chunks[1],
    );

    if jump.filtered.is_empty() {
        frame.render_widget(
            Paragraph::new(Line::from(Span::styled(
                "No conversations or threads match that filter.",
                Style::default().fg(MUTED),
            ))),
            chunks[2],
        );
    } else {
        let items: Vec<ListItem> = jump
            .filtered
            .iter()
            .map(|index| {
                let entry = &jump.all[*index];
                let kind = entry.kind.label();
                let colour = match entry.kind {
                    JumpKind::Chat => BLUE,
                    JumpKind::Thread => ACCENT,
                };
                ListItem::new(vec![
                    Line::from(vec![
                        Span::styled(
                            format!(" {kind:<6} "),
                            Style::default().fg(colour).add_modifier(Modifier::BOLD),
                        ),
                        Span::styled(
                            fit(&entry.title, chunks[2].width.saturating_sub(10) as usize),
                            Style::default().fg(INK),
                        ),
                    ]),
                    Line::from(vec![
                        Span::styled("        ", theme::base()),
                        Span::styled(
                            fit(&entry.meta, chunks[2].width.saturating_sub(10) as usize),
                            theme::hint(),
                        ),
                    ]),
                ])
            })
            .collect();
        let list = List::new(items).highlight_style(
            Style::default()
                .bg(SELECT_FOCUS)
                .fg(ratatui::style::Color::Rgb(243, 248, 245)),
        );
        let mut state = ListState::default();
        state.select(Some(jump.selected.min(jump.filtered.len() - 1)));
        frame.render_stateful_widget(list, chunks[2], &mut state);
    }

    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::styled(" enter ", theme::key_chip()),
            Span::styled(" jump   ", theme::hint()),
            Span::styled(" esc ", theme::key_chip()),
            Span::styled(" cancel   ", theme::hint()),
            Span::styled(" ↑/↓ ", theme::key_chip()),
            Span::styled(" move", theme::hint()),
        ])),
        chunks[3],
    );
}
