---
name: codex-network
description: Use the local codex-network helper for Codex conversation networking and HTTP forwarding across the parent Mac and subscribed RDEs, especially when asked to list all sessions, send messages by conversation id, continue another chat, or expose a localhost service between environments.
---

# Codex Network

## Category

Infrastructure Operations

## Use when

- the user wants to list Codex conversations across local and RDE sessions
- the user wants to send a message to another Codex chat by conversation id
- the user asks whether an RDE/local session can communicate with another chat
- the user wants to expose or access a localhost HTTP service across the parent machine and subscribed RDEs
- the user asks for the native/non-reinvented way this network is implemented

## Default workflow

1. Prefer `codex-network` before manually opening Codex state databases, SSHing into every RDE, or exposing raw app-server URLs.
2. Check availability:

   ```bash
   command -v codex-network
   codex-network http list
   ```

3. List conversations across subscribed nodes:

   ```bash
   codex-network list --limit 1000
   ```

4. Send to another chat by id:

   ```bash
   codex-network send <conversation-id> --message "<message>"
   ```

5. Expose an HTTP service from an explicit node:

   ```bash
   codex-network http expose <node>:<port> --name <name>
   codex-network http url <name>
   ```

6. Expose an HTTP service from the node owning a conversation:

   ```bash
   codex-network http expose --conversation-id <conversation-id> --port <port> --name <name>
   codex-network http url <name>
   ```

7. List or stop active forwards:

   ```bash
   codex-network http list
   codex-network http stop <name>
   ```

## Rules

- Keep the user-facing path high level: conversation ids, forward names, nodes, and ports.
- Do not expose raw app-server URLs, hidden internal commands, or raw tunnel commands unless debugging requires it.
- Creating or stopping mesh HTTP forwards should run from the parent machine for now; RDEs can list forwards, resolve names, and use the returned localhost URL.
- Prefer named HTTP forwards over ad hoc one-off SSH tunnels.
- After creating a forward, verify the URL from the parent and at least one RDE.
- Stop temporary smoke-test forwards before finishing unless the user explicitly wants the forward left running.

## Under The Hood

- Conversation messaging uses Codex app-server v2 JSON-RPC over the built-in WebSocket transport.
- HTTP forwarding uses SSH `-L` and `-R` tunnels managed by tmux.
- Parent-local port remapping uses a tiny Node TCP proxy.
- Node registry: `~/.codex-network/nodes.tsv`
- HTTP registry: `~/.codex-network/http.tsv`

## Gotchas

- If `codex-network list` cannot scan an RDE, restore the parent app-server SSH forward for that node before relying on conversation-id resolution.
- `http expose --conversation-id` still needs `--port`; the conversation resolves the owning node, not the application port.
- RDEs need the helper copied to `~/.local/bin/codex-network` and the node registry synced before they can resolve all nodes.
- Do not print Codex credentials, OAuth tokens, or private app-server payloads.

## Stop conditions

- Stop and report if SSH to a target RDE fails.
- Stop and report if the target HTTP port is not listening.
- Stop and report if a conversation id is ambiguous across subscribed nodes.
