#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ssh_config="${CODEX_NETWORK_SSH_CONFIG:-$HOME/.ssh/config}"

if [[ ! -f "$ssh_config" ]]; then
  echo "missing SSH config: $ssh_config" >&2
  exit 1
fi

hosts=()
while IFS= read -r host; do
  [[ -n "$host" ]] && hosts+=("$host")
done < <(
  awk '
    $1 == "#" && $0 ~ /BEGIN Codex RDE aliases/ { in_block = 1; next }
    $1 == "#" && $0 ~ /END Codex RDE aliases/ { in_block = 0 }
    in_block && tolower($1) == "host" {
      for (i = 2; i <= NF; i++) {
        if ($i !~ /[*?]/) print $i
      }
    }
  ' "$ssh_config" | sort -u
)

if [[ ${#hosts[@]} -eq 0 ]]; then
  echo "no RDE hosts found in $ssh_config" >&2
  exit 1
fi

for host in "${hosts[@]}"; do
  [[ "$host" =~ ^[A-Za-z0-9_.@-]+$ ]] || {
    echo "refusing unsafe SSH host alias: $host" >&2
    exit 1
  }

  echo "syncing $host"
  ssh -o BatchMode=yes -o ConnectTimeout=20 "$host" 'mkdir -p ~/.local/bin ~/.agents/skills && rm -rf ~/.agents/skills/codex-network'
  scp -q "$repo_dir/bin/codex-network" "$host:~/.local/bin/codex-network"
  scp -q -r "$repo_dir/skills/codex-network" "$host:~/.agents/skills/codex-network"
  ssh -o BatchMode=yes -o ConnectTimeout=20 "$host" \
    'chmod +x ~/.local/bin/codex-network && bash -n ~/.local/bin/codex-network && test -f ~/.agents/skills/codex-network/SKILL.md'
done

echo "synced codex-network helper and skill to ${#hosts[@]} RDE(s)"
