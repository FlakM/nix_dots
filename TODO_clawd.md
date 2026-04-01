1. Persist shell state in `/var/home/flakm` (`.bash_history`, `.zsh_history`, Atuin data).
2. Keep `zsh` and `atuin` available in the guest by default.
3. Treat `/home/flakm` as persistent state backed by `/var/home/flakm`.
4. Do not mount host `~/.claude`; initialize OpenClaw manually with `openai-codex` inside the VM.
5. Keep the VM declarative for config and secrets, but keep provider auth local to the VM runtime state.
