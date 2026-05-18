# Contributing

This project is intentionally small: a Bash CLI, a Codex skill, and install/sync
scripts.

Before sending a change:

```bash
scripts/check.sh
```

Keep user-facing commands high level. Prefer conversation ids, node names,
forward names, and ports over exposing raw WebSocket URLs or SSH tunnel
arguments in normal workflows.
