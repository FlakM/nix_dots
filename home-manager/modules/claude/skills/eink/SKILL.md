---
name: eink
description: Push content to Boox e-ink tablet for review, block until notes come back.
---

# E-Ink Review

Push content to the Boox for reading and annotation. Blocks until the user submits their review, then returns typed notes and annotation image paths as context.

## Usage

```
/eink [file]
```

- If a file path is given, push that file.
- If no argument, push the last assistant message as markdown.

## Steps

1. Determine content to push:
   - If the user provided a file path argument, use that file directly.
   - Otherwise, write the last substantial assistant response to a temporary markdown file.

2. Run the CLI (blocking):
```bash
eink-review push --timeout 30 <file>
```

3. The command blocks until the Boox user submits their review or the timeout expires.

4. On success (exit 0): the stdout contains typed notes and annotation image paths. Include the full output in your response as context. If annotation images are listed, read them with the Read tool so you can see the handwritten content.

5. On failure (exit 1): report the error (timeout, cancelled, server not running).

## Important

- The `eink-serve` systemd service must be running. If the command fails with a connection error, tell the user to start it: `systemctl --user start eink-serve`
- Do NOT proceed with other work while waiting — the review is the user's input.
- After receiving notes, acknowledge what the user wrote and continue the conversation informed by their feedback.
