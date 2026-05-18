#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ssh_config="${CODEX_NETWORK_SSH_CONFIG:-$HOME/.ssh/config}"
hosts_file="${CODEX_NETWORK_HOSTS_FILE:-$HOME/.codex-network/hosts}"

# shellcheck disable=SC1091
source "$repo_dir/lib/codex-network/hosts.bash"

hosts=()
while IFS= read -r host; do
  [[ -n "$host" ]] && hosts+=("$host")
done < <(discover_codex_network_hosts "$hosts_file" "$ssh_config")

if [[ ${#hosts[@]} -eq 0 ]]; then
  echo "no remote hosts found; set CODEX_NETWORK_SSH_HOSTS, create $hosts_file, or add a codex-network hosts block to $ssh_config" >&2
  exit 1
fi

for host in "${hosts[@]}"; do
  validate_codex_network_host_alias "$host" || {
    echo "refusing unsafe SSH host alias: $host" >&2
    exit 1
  }

  echo "syncing $host"
  ssh -o BatchMode=yes -o ConnectTimeout=20 "$host" 'mkdir -p ~/.local/bin ~/.local/lib ~/.agents/skills && rm -rf ~/.agents/skills/codex-network ~/.local/lib/codex-network'
  scp -q "$repo_dir/bin/codex-network" "$host:~/.local/bin/codex-network"
  scp -q -r "$repo_dir/lib/codex-network" "$host:~/.local/lib/codex-network"
  scp -q -r "$repo_dir/skills/codex-network" "$host:~/.agents/skills/codex-network"
  ssh -o BatchMode=yes -o ConnectTimeout=20 "$host" \
    'chmod +x ~/.local/bin/codex-network && bash -n ~/.local/bin/codex-network && test -f ~/.local/lib/codex-network/rpc.mjs && test -f ~/.agents/skills/codex-network/SKILL.md'
done

echo "synced codex-network helper and skill to ${#hosts[@]} remote host(s)"
