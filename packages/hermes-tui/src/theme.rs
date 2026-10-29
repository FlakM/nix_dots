//! Colour palette and small style helpers shared by the UI modules.

use ratatui::style::{Color, Modifier, Style};

pub const BG: Color = Color::Rgb(9, 13, 17);
pub const PANEL: Color = Color::Rgb(14, 20, 26);
pub const BORDER: Color = Color::Rgb(28, 38, 45);
pub const INK: Color = Color::Rgb(215, 227, 224);
pub const MUTED: Color = Color::Rgb(125, 143, 138);
pub const HINT: Color = Color::Rgb(174, 191, 185);
pub const FAINT: Color = Color::Rgb(75, 91, 87);
pub const ACCENT: Color = Color::Rgb(114, 228, 174);
pub const BLUE: Color = Color::Rgb(114, 215, 255);
pub const AMBER: Color = Color::Rgb(246, 193, 119);
pub const RED: Color = Color::Rgb(255, 123, 134);
pub const PURPLE: Color = Color::Rgb(195, 166, 255);
pub const SELECT: Color = Color::Rgb(29, 59, 41);
pub const SELECT_FOCUS: Color = Color::Rgb(42, 90, 61);
pub const KEY_BG: Color = Color::Rgb(24, 39, 46);

pub fn base() -> Style {
    Style::default().bg(BG).fg(INK)
}

pub fn panel() -> Style {
    Style::default().bg(PANEL).fg(MUTED)
}

pub fn key() -> Style {
    Style::default().fg(ACCENT).add_modifier(Modifier::BOLD)
}

pub fn hint() -> Style {
    Style::default().fg(HINT)
}

pub fn key_chip() -> Style {
    Style::default()
        .bg(KEY_BG)
        .fg(ACCENT)
        .add_modifier(Modifier::BOLD)
}

pub fn dim() -> Style {
    Style::default().fg(FAINT)
}

pub fn online() -> Style {
    Style::default().fg(ACCENT)
}

pub fn warning() -> Style {
    Style::default().fg(AMBER).add_modifier(Modifier::BOLD)
}

pub fn error() -> Style {
    Style::default().fg(RED).add_modifier(Modifier::BOLD)
}
