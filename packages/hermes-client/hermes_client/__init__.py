"""Desktop clients for the Hermes agent HTTP API.

Three entry points are installed from this package:

``hermes``        non-interactive CLI (scriptable, ``--json`` everywhere)
``hermes-tui``    textual dashboard for tracked threads and running jobs
``hermes-bridge`` systemd user service feeding desktop toasts + quickshell

The wire format is defined in ``PLATFORM.md`` (section "HTTP API") in the
hermes-agent module.  Everything here is a client: no state is owned locally
except the bridge cache under ``~/.cache/hermes``.
"""

__version__ = "1.0.0"
