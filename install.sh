#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -d "$HOME/.local/bin"
install -m 0755 "$repo_dir/bin/codex-network" "$HOME/.local/bin/codex-network"

if [[ -d "$HOME/src/dotagents/skills" ]]; then
  rm -rf "$HOME/src/dotagents/skills/codex-network"
  mkdir -p "$HOME/src/dotagents/skills"
  cp -R "$repo_dir/skills/codex-network" "$HOME/src/dotagents/skills/codex-network"
fi

echo "installed codex-network to $HOME/.local/bin/codex-network"
