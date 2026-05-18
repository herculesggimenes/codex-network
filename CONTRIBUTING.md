# Contributing

This project is intentionally small: a Bash CLI, a Codex skill, and install/sync scripts.

Use Node.js 24 or newer for the validation toolchain.

Before sending a change:

```bash
npm ci
npm run check
```

Keep user-facing commands high level. Prefer conversation ids, node names, forward names, and ports
over exposing raw WebSocket URLs or SSH tunnel arguments in normal workflows.
