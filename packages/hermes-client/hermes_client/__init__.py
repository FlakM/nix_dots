"""Desktop clients for the Hermes agent HTTP API.

Two entry points are installed from this package:

``hermes``        non-interactive CLI (scriptable, ``--json`` everywhere)
``hermes-bridge`` systemd user service feeding desktop toasts + quickshell

The interactive dashboard lives in the Rust ``hermes-tui`` package
(ratatui); it reads the same ``~/.config/hermes/client.env``.

The wire format is defined in ``PLATFORM.md`` (section "HTTP API") in the
hermes-agent module.  Everything here is a client: no state is owned locally
except the bridge cache under ``~/.cache/hermes``.
"""

__version__ = "1.1.0"
