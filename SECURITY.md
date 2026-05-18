# Security

`codex-network` is designed for private localhost and SSH-scoped workflows.

Supported boundaries:

- Codex app-server endpoints should bind to `127.0.0.1`.
- HTTP forwards created by this helper bind to `127.0.0.1`.
- The parent forwarding control endpoint binds to `127.0.0.1` and only accepts validated
  `http expose` and `http stop` requests.
- Remote access is delegated to your existing SSH configuration and keys.
- Conversation messaging uses the local Codex app-server API and does not need separate API tokens.

Do not expose Codex app-server ports, forwarded HTTP ports, or generated registry files to a public
network. If you find a security issue, open a private advisory on GitHub or contact the maintainer
directly.
