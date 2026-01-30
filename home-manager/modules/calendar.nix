{ config, pkgs, lib, ... }:
{
  home.packages = with pkgs; [
    vdirsyncer
    khal
  ];

  xdg.configFile."vdirsyncer/config".text = ''
    [general]
    status_path = "~/.local/share/vdirsyncer/status/"

    # Coralogix work calendar
    [pair coralogix_calendar]
    a = "coralogix_google"
    b = "coralogix_local"
    collections = ["from a"]
    conflict_resolution = "a wins"

    [storage coralogix_google]
    type = "google_calendar"
    token_file = "~/.local/share/vdirsyncer/coralogix_token"
    client_id.fetch = ["command", "cat", "${config.home.homeDirectory}/.google_oauth_client_id"]
    client_secret.fetch = ["command", "cat", "${config.home.homeDirectory}/.google_oauth_client_secret"]

    [storage coralogix_local]
    type = "filesystem"
    path = "~/.local/share/vdirsyncer/calendars/coralogix/"
    fileext = ".ics"

    # Personal calendar
    [pair personal_calendar]
    a = "personal_google"
    b = "personal_local"
    collections = ["from a"]
    conflict_resolution = "a wins"

    [storage personal_google]
    type = "google_calendar"
    token_file = "~/.local/share/vdirsyncer/personal_token"
    client_id.fetch = ["command", "cat", "${config.home.homeDirectory}/.google_oauth_client_id"]
    client_secret.fetch = ["command", "cat", "${config.home.homeDirectory}/.google_oauth_client_secret"]

    [storage personal_local]
    type = "filesystem"
    path = "~/.local/share/vdirsyncer/calendars/personal/"
    fileext = ".ics"
  '';

  xdg.configFile."khal/config".text = ''
    [calendars]

    [[coralogix]]
    path = ~/.local/share/vdirsyncer/calendars/coralogix/*
    type = discover
    color = dark cyan

    [[personal]]
    path = ~/.local/share/vdirsyncer/calendars/personal/*
    type = discover
    color = dark magenta

    [locale]
    timeformat = %H:%M
    dateformat = %d.%m.
    longdateformat = %d.%m.%Y
    datetimeformat = %d.%m. %H:%M
    longdatetimeformat = %d.%m.%Y %H:%M
    firstweekday = 0

    [default]
    default_calendar = maciej.flak@coralogix.com
    highlight_event_days = True
  '';

  home.activation.createVdirsyncerDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ~/.local/share/vdirsyncer/status
    mkdir -p ~/.local/share/vdirsyncer/calendars
  '';

  systemd.user.services.vdirsyncer-sync = {
    Unit = {
      Description = "Sync calendars with vdirsyncer";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.vdirsyncer}/bin/vdirsyncer sync";
    };
  };

  systemd.user.timers.vdirsyncer-sync = {
    Unit = {
      Description = "Sync calendars every 15 minutes";
    };
    Timer = {
      OnBootSec = "5m";
      OnUnitActiveSec = "15m";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  home.file.".local/bin/khal-next".source = pkgs.writeShellScript "khal-next" ''
    #!/usr/bin/env bash
    next=$(${pkgs.khal}/bin/khal list now 2h --format "{start-time} {title}" 2>/dev/null | grep -E "^[0-9]{2}:[0-9]{2}" | head -1)
    if [ -n "$next" ]; then
      time=$(echo "$next" | cut -d' ' -f1)
      title=$(echo "$next" | cut -d' ' -f2- | cut -c1-25)
      grey=$(${pkgs.ncurses}/bin/tput setaf 8)
      reset=$(${pkgs.ncurses}/bin/tput sgr0)
      printf '%s %s%s%s\n' "$time" "$grey" "$title" "$reset"
    fi
  '';

  home.file.".local/bin/khal-waybar".source = pkgs.writeShellScript "khal-waybar" ''
    #!/usr/bin/env bash

    # Get next event from all calendars in the next 8 hours
    next=$(${pkgs.khal}/bin/khal list now 8h --format "{start-time} {title}" 2>/dev/null | grep -E "^[0-9]{2}:[0-9]{2}" | head -1)

    # Get today's full agenda for tooltip
    tooltip=$(${pkgs.khal}/bin/khal list today tomorrow --format "{start-time} {title}" 2>/dev/null | head -15 | sed 's/"/\\"/g' | paste -sd'|' - | sed 's/|/\\n/g')

    if [ -n "$next" ]; then
      next_time=$(echo "$next" | cut -d' ' -f1)
      event_title=$(echo "$next" | cut -d' ' -f2- | cut -c1-25)

      current_minutes=$((10#$(date +%H) * 60 + 10#$(date +%M)))
      event_hour=$(echo "$next_time" | cut -d: -f1)
      event_min=$(echo "$next_time" | cut -d: -f2)
      event_minutes=$((10#$event_hour * 60 + 10#$event_min))
      diff=$((event_minutes - current_minutes))

      if [ $diff -le 15 ] && [ $diff -ge -5 ]; then
        class="urgent"
      elif [ $diff -le 60 ]; then
        class="has-events"
      else
        class="has-events"
      fi
      text="$next_time $event_title"
    else
      class="no-events"
      text="No events"
      tooltip="No upcoming events today"
    fi

    printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$text" "$tooltip" "$class"
  '';

  home.file.".local/bin/khal-notify".source = pkgs.writeShellScript "khal-notify" ''
    #!/usr/bin/env bash

    # Get today's and tomorrow's agenda
    agenda=$(${pkgs.khal}/bin/khal list today tomorrow --format "{start-time}-{end-time} {title}" 2>/dev/null | head -20)

    if [ -n "$agenda" ]; then
      ${pkgs.libnotify}/bin/notify-send -t 10000 "Calendar" "$agenda"
    else
      ${pkgs.libnotify}/bin/notify-send -t 5000 "Calendar" "No upcoming events"
    fi
  '';
}
