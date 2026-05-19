---
name: codex-network
description:
  "Use codex-network whenever work needs to cross Codex environments: list or message Codex chats
  across the parent machine and subscribed remote hosts/RDEs, continue or steer another conversation
  by conversation id, validate conversation ids across workspaces, expose/share/forward a localhost
  HTTP port, open a parent-machine browser from a remote/RDE session, handle OAuth links or
  localhost callbacks across environments, start a dev server that must be reachable from another
  environment, verify a URL from a remote host, or hand off work between local and remote sessions
  without exposing raw SSH, tmux, or app-server details."
---

# Codex Network

## Category

Infrastructure Operations

## Use Whenever

- the user asks to list all Codex sessions, chats, conversations, threads, remote/RDE sessions, or
  local sessions
- the user wants to send, continue, steer, wake up, or hand off work to another Codex chat by
  conversation id
- the user asks to validate, double-check, audit, verify, or diagnose conversation ids across local
  and remote/RDE workspaces
- the user asks whether local and remote/RDE sessions can communicate with each other or with a
  parent chat
- the user says port forwarding, port-forwarding, forward a port, expose a port, share localhost,
  open a local service from another node, or make one environment reach another environment's port
- the user asks to open a browser from an RDE, open a local URL on the parent machine, complete an
  OAuth browser flow from a remote environment, or open a forwarded localhost URL
- a task starts a localhost server, dev server, preview server, app server, HTTP API, webhook
  receiver, Storybook, Vite app, Next app, Rails app, dashboard, or other port that may need to be
  opened from another environment
- the user asks to share work between local and remote/RDE hosts, share a running app, expose a
  port, forward a port, open a URL from a remote host, make a service reachable from the parent
  machine, or make one remote host reach another host's local server
- the user asks to dogfood, browser-test, smoke-test, or inspect a web app that is running in a
  different Codex environment
- the user wants the native/non-reinvented implementation for cross-environment Codex communication

## Default Routing

1. Prefer `codex-network` before manual SSH loops, raw `ssh -L` or `ssh -R`, direct Codex
   state-database reads, raw app-server URLs, or bespoke tunnel scripts.
2. Keep the user-facing interface high level: conversation ids, forward names, node names, and
   ports.
3. If the task is about conversations or work handoff, use the conversation commands.
4. If the task is about a running localhost service, URL, browser preview, dev server, webhook
   receiver, or any port, use the HTTP forward commands.
5. Create or stop mesh HTTP forwards from whichever node you are on. Remote/RDE nodes delegate the
   request to the parent control endpoint when `codex-network expose-parent --all-hosts` has been
   run on the parent.
6. If an RDE needs a human/browser action, use the browser commands so the parent machine opens the
   URL. For OAuth, expose the callback port first when the redirect URI points at localhost.

## Availability Check

```bash
command -v codex-network
codex-network http list
```

Use `codex-network http list` as the cheap health check because it does not require starting or
probing every Codex app-server.

## Conversation Commands

List conversations across subscribed nodes:

```bash
codex-network list --limit 1000
```

Find a specific conversation by scanning the list:

```bash
codex-network list --limit 1000 --search "<text>"
```

Send or steer a message to another chat by id:

```bash
codex-network send <conversation-id> --message "<message>"
```

Use this when the user says to continue another chat, tell another session something, keep
conversations flowing, pass context to a remote host/RDE, or send an instruction directly into a
running session.

Validate conversation-id routing across nodes and workspaces:

```bash
codex-network doctor conversations --limit 100
codex-network doctor conversations --workspace <cwd>
```

Use this when the user asks whether conversation ids are working everywhere. It lists recent
conversations by workspace and verifies each id resolves back to the same node/thread.

## HTTP Forward Commands

Expose a service from an explicit node:

```bash
codex-network http expose <node>:<port> --name <name>
codex-network http url <name>
```

Expose a service from the node that owns a conversation:

```bash
codex-network http expose --conversation-id <conversation-id> --port <port> --name <name>
codex-network http url <name>
```

List or stop active forwards:

```bash
codex-network http list
codex-network http stop <name>
```

Set up remote/RDE control of parent-owned forwards:

```bash
codex-network expose-parent --all-hosts
codex-network control status
```

After this setup, a remote/RDE can run the same `codex-network http expose ...` and
`codex-network http stop ...` commands. If no target node is supplied, a synced remote defaults to
its `~/.codex-network/node` identity.

Open a named forward or URL in the parent browser from any subscribed node:

```bash
codex-network open <forward-name>
codex-network open "<http-or-https-url>"
```

For OAuth from an RDE:

```bash
codex-network http expose --port <callback-port> --listen-port <callback-port> --name oauth-callback
codex-network open "<authorization-url>"
```

After creating a forward, verify the returned URL from the parent and at least one relevant remote
host:

```bash
curl -fsS "$(codex-network http url <name>)"
ssh <remote-host> 'curl -fsS "$(codex-network http url <name>)"'
```

## Port-Sharing Policy

- When starting a server that may be inspected outside its origin environment, start it bound to
  `127.0.0.1` in the origin environment, then expose it with a named `codex-network http expose`
  forward.
- Prefer names that identify the work, not the mechanism, for example `review-app`,
  `storybook-pr-123`, `worker-webhook`, or `wren-preview`.
- If the service belongs to a conversation, prefer `--conversation-id <id> --port <port>` so the
  node is resolved instead of hard-coded.
- If the user only asks to start a server and there is any chance they need to open it from another
  environment, mention the forward name and URL after exposing it.
- Stop temporary smoke-test forwards before finishing unless the user asked to leave the shared port
  running.

## Under The Hood

- Conversation messaging uses Codex app-server v2 JSON-RPC over the built-in WebSocket transport.
- HTTP forwarding uses native SSH `-L` and `-R` tunnels managed by tmux.
- Parent-local port remapping uses a tiny Node TCP proxy.
- Remote/RDE port-forward control uses a parent-local HTTP control server exposed to each remote
  over SSH `-R`; the server only accepts validated `http expose`, `http stop`, and browser-open
  requests.
- Node registry: `~/.codex-network/nodes.tsv`
- HTTP registry: `~/.codex-network/http.tsv`

## Gotchas

- `http expose --conversation-id` still needs `--port`; the conversation resolves the owning node,
  not the application port.
- Remote/RDE create/stop requests require the parent control tunnel from
  `codex-network expose-parent --all-hosts`.
- Remote/RDE browser-open requests also require the parent control tunnel from
  `codex-network expose-parent --all-hosts`.
- Browser-open only accepts `http://` and `https://` URLs. Do not pass `file://` URLs or shell
  command strings.
- If `codex-network list` cannot scan a remote host/RDE, restore the parent app-server SSH forward
  for that node before relying on conversation-id resolution.
- Remote hosts/RDEs need `~/.local/bin/codex-network`, `~/.local/lib/codex-network`, and
  `~/.codex-network/nodes.tsv` synced before they can resolve all nodes. `scripts/sync-remotes.sh`
  writes a remote-specific `nodes.tsv` plus `~/.codex-network/node` so each RDE can resolve the
  parent, itself, and other subscribed nodes.
- Do not print Codex credentials, OAuth tokens, private app-server payloads, or raw internal tunnel
  details unless debugging requires a narrow excerpt.

## Stop Conditions

- Stop and report if SSH to a target remote host fails.
- Stop and report if the target HTTP port is not listening.
- Stop and report if a conversation id is ambiguous across subscribed nodes.
- Stop and report if a requested share would require exposing a service beyond localhost; this
  helper is designed for `127.0.0.1`-scoped forwards.
