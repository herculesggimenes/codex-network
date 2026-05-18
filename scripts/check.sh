#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

echo "checking shell syntax"
bash -n bin/codex-network install.sh scripts/sync-remotes.sh scripts/sync-rdes.sh lib/codex-network/hosts.bash
echo "checking Node helper syntax"
node --check lib/codex-network/rpc.mjs
echo "checking Node WebSocket runtime"
node -e 'if (!globalThis.WebSocket) process.exit(1)'
echo "checking CLI smoke paths"
bin/codex-network --help >/dev/null
bin/codex-network http list >/dev/null

echo "checking host discovery"
actual="$(
  CODEX_NETWORK_SSH_HOSTS='beta,alpha alpha' bash -lc '
    source lib/codex-network/hosts.bash
    discover_codex_network_hosts /tmp/missing-codex-network-hosts /tmp/missing-codex-network-ssh-config
  '
)"
expected=$'alpha\nbeta'
[[ "$actual" == "$expected" ]] || {
  printf 'unexpected env host discovery output:\n%s\n' "$actual" >&2
  exit 1
}

echo "checking install layout"
tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT
HOME="$tmp_home" ./install.sh >/dev/null
HOME="$tmp_home" "$tmp_home/.local/bin/codex-network" --help >/dev/null
test -f "$tmp_home/.local/lib/codex-network/rpc.mjs"
test -f "$tmp_home/.agents/skills/codex-network/SKILL.md"
