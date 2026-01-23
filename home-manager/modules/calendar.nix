{ config, pkgs, lib, ... }:
{
  home.packages = with pkgs; [
    vdirsyncer
    khal
  ];

  xdg.configFile."vdirsyncer/config".text = ''
    [general]
    status_path = "~/.local/share/vdirsyncer/status/"

    [pair google_calendar]
    a = "google"
    b = "google_local"
    collections = ["from a"]
    conflict_resolution = "a wins"

    [storage google]
    type = "google_calendar"
    token_file = "~/.local/share/vdirsyncer/google_token"
    client_id.fetch = ["command", "cat", "${config.home.homeDirectory}/.gmail_oauth_client_id"]
    client_secret.fetch = ["command", "cat", "${config.home.homeDirectory}/.gmail_oauth_client_secret"]

    [storage google_local]
    type = "filesystem"
    path = "~/.local/share/vdirsyncer/calendars/"
    fileext = ".ics"
  '';

  xdg.configFile."khal/config".text = ''
    [calendars]

    [[google]]
    path = ~/.local/share/vdirsyncer/calendars/*
    type = discover

    [locale]
    timeformat = %H:%M
    dateformat = %d.%m.
    longdateformat = %d.%m.%Y
    datetimeformat = %d.%m. %H:%M
    longdatetimeformat = %d.%m.%Y %H:%M
    firstweekday = 0

    [default]
    default_calendar = None
    highlight_event_days = True
  '';

  home.activation.createVdirsyncerDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ~/.local/share/vdirsyncer/status
    mkdir -p ~/.local/share/vdirsyncer/calendars
  '';
}
