//! `hermes-tui` — conversations, tracked threads and live agent jobs.
//!
//! A ratatui front end for the Hermes HTTP API. Chat is a first-class tab:
//! pressing `n` (or just typing) starts a new conversation thread, and
//! follow-up messages carry the transcript as context.
//!
//! Configuration is the same `~/.config/hermes/client.env` as the CLI:
//! `HERMES_API_URL` and `HERMES_API_TOKEN_FILE`.

mod api;
mod app;
mod chat;
mod commands;
mod config;
mod events;
mod model;
mod store;
mod theme;
mod ui;

use anyhow::{Context, Result};
use app::{App, AppEvent};
use crossterm::event::{self, EnableBracketedPaste};
use crossterm::execute;
use std::io::Write;
use std::sync::mpsc;
use std::time::Duration;

const HELP: &str = "\
hermes-tui — Hermes conversations, tracked threads and live jobs

Usage:
  hermes-tui             open the dashboard
  hermes-tui --help      this text
  hermes-tui --version   print the version

Inside the app:
  1 / 2 / 3   Chat, Threads, Jobs        tab   next tab
  n           start a new conversation   :     command bar
  ?           full key and command help  q     quit

Configuration (~/.config/hermes/client.env, written by home-manager):
  HERMES_API_URL=https://hermes.house.flakm.com
  HERMES_API_TOKEN_FILE=/run/user/1000/secrets/hermes_api_token
";

fn main() -> Result<()> {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    if arguments
        .iter()
        .any(|argument| argument == "-h" || argument == "--help")
    {
        print!("{HELP}");
        return Ok(());
    }
    if arguments
        .iter()
        .any(|argument| argument == "-V" || argument == "--version")
    {
        println!("hermes-tui {}", env!("CARGO_PKG_VERSION"));
        return Ok(());
    }

    let (tx, rx) = mpsc::channel::<AppEvent>();
    let mut terminal = ratatui::init();
    let _ = execute!(std::io::stdout(), EnableBracketedPaste);

    let input_tx = tx.clone();
    let _ = std::thread::Builder::new()
        .name("hermes-input".to_string())
        .spawn(move || input_loop(input_tx));

    let mut app = App::bootstrap(tx, rx);
    let result = run(&mut terminal, &mut app);

    app.stop();
    let _ = execute!(std::io::stdout(), crossterm::event::DisableBracketedPaste);
    ratatui::restore();
    let _ = std::io::stdout().flush();
    result
}

fn run(terminal: &mut ratatui::DefaultTerminal, app: &mut App) -> Result<()> {
    while !app.should_quit {
        terminal
            .draw(|frame| ui::draw(frame, app))
            .context("cannot draw the terminal")?;
        match app.receiver().recv() {
            Ok(event) => {
                app.handle(event);
                // Drain queued events (a burst of SSE frames or a paste) before
                // redrawing, so frames stay cheap.
                while let Ok(event) = app.receiver().try_recv() {
                    app.handle(event);
                    if app.should_quit {
                        break;
                    }
                }
            }
            Err(_) => break,
        }
    }
    Ok(())
}

fn input_loop(tx: mpsc::Sender<AppEvent>) {
    loop {
        match event::poll(Duration::from_millis(100)) {
            Ok(true) => match event::read() {
                Ok(event::Event::Key(key)) => {
                    if tx.send(AppEvent::Input(key)).is_err() {
                        return;
                    }
                }
                Ok(event::Event::Paste(text)) => {
                    if tx.send(AppEvent::Paste(text)).is_err() {
                        return;
                    }
                }
                Ok(_) => {}
                Err(_) => return,
            },
            Ok(false) => {
                if tx.send(AppEvent::Tick).is_err() {
                    return;
                }
            }
            Err(_) => return,
        }
    }
}
