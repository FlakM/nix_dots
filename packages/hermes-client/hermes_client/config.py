"""Client configuration.

Read from ``~/.config/hermes/client.env`` (written by home-manager)::

    HERMES_API_URL=https://hermes.house.flakm.com
    HERMES_API_TOKEN_FILE=/run/user/1000/secrets/hermes_api_token

Environment variables win over the file so the CLI stays easy to point at a
development server.  The token itself is always read from the file named by
``HERMES_API_TOKEN_FILE``; a literal ``HERMES_API_TOKEN`` is accepted for tests.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

DEFAULT_API_URL = "https://hermes.house.flakm.com"


class ConfigError(RuntimeError):
    """Configuration is missing or unusable (one-line message for humans)."""


def cache_dir() -> Path:
    """``~/.cache/hermes`` (honours ``XDG_CACHE_HOME``)."""
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(Path.home(), ".cache")
    return Path(base) / "hermes"


def env_file_path() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(Path.home(), ".config")
    return Path(base) / "hermes" / "client.env"


def parse_env(text: str) -> dict[str, str]:
    """Tiny ``KEY=VALUE`` parser; comments and optional quotes/``export``."""
    values: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].lstrip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if key:
            values[key] = value
    return values


def normalize_url(url: str) -> str:
    url = url.strip().rstrip("/")
    if not url:
        raise ConfigError("HERMES_API_URL is empty")
    if not url.startswith(("http://", "https://")):
        raise ConfigError(f"HERMES_API_URL must start with http:// or https:// (got {url!r})")
    # nginx exposes the API under /api/, the client adds that itself.
    if url.endswith("/api"):
        url = url[: -len("/api")]
    return url


@dataclass(frozen=True)
class Config:
    api_url: str
    token: str
    token_file: str | None = None
    env_file: str | None = None


def load_config(path: str | os.PathLike[str] | None = None) -> Config:
    """Load and validate the client config, or raise :class:`ConfigError`."""
    env_path = Path(path).expanduser() if path else env_file_path()
    file_values: dict[str, str] = {}
    if env_path.is_file():
        try:
            file_values = parse_env(env_path.read_text(encoding="utf-8"))
        except OSError as exc:
            raise ConfigError(f"cannot read {env_path}: {exc}") from exc

    api_url = normalize_url(
        os.environ.get("HERMES_API_URL") or file_values.get("HERMES_API_URL") or DEFAULT_API_URL
    )

    token = os.environ.get("HERMES_API_TOKEN", "").strip()
    token_file = os.environ.get("HERMES_API_TOKEN_FILE") or file_values.get("HERMES_API_TOKEN_FILE") or None
    if not token:
        if not token_file:
            raise ConfigError(
                "no Hermes API token configured "
                f"(set HERMES_API_TOKEN_FILE in {env_path})"
            )
        token_path = Path(token_file).expanduser()
        try:
            token = token_path.read_text(encoding="utf-8").strip()
        except OSError as exc:
            raise ConfigError(
                f"cannot read Hermes API token {token_path}: {exc.strerror or exc}"
            ) from exc
        if not token:
            raise ConfigError(f"Hermes API token file {token_path} is empty")
        token_file = str(token_path)

    return Config(
        api_url=api_url,
        token=token,
        token_file=token_file,
        env_file=str(env_path) if env_path.exists() else None,
    )
