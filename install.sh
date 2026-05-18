#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -d "$HOME/.local/bin"
install -m 0755 "$repo_dir/bin/codex-network" "$HOME/.local/bin/codex-network"

install -d "$HOME/.local/lib"
rm -rf "$HOME/.local/lib/codex-network"
cp -R "$repo_dir/lib/codex-network" "$HOME/.local/lib/codex-network"

install -d "$HOME/.agents/skills"
rm -rf "$HOME/.agents/skills/codex-network"
cp -R "$repo_dir/skills/codex-network" "$HOME/.agents/skills/codex-network"

if [[ -n "${CODEX_NETWORK_EXTRA_SKILLS_DIR:-}" ]]; then
  install -d "$CODEX_NETWORK_EXTRA_SKILLS_DIR"
  rm -rf "$CODEX_NETWORK_EXTRA_SKILLS_DIR/codex-network"
  cp -R "$repo_dir/skills/codex-network" "$CODEX_NETWORK_EXTRA_SKILLS_DIR/codex-network"
  echo "installed codex-network skill to $CODEX_NETWORK_EXTRA_SKILLS_DIR/codex-network"
fi

echo "installed codex-network to $HOME/.local/bin/codex-network"
echo "installed codex-network library to $HOME/.local/lib/codex-network"
echo "installed codex-network skill to $HOME/.agents/skills/codex-network"
