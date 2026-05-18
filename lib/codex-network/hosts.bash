discover_codex_network_hosts() {
  local hosts_file="${1:-${CODEX_NETWORK_HOSTS_FILE:-$HOME/.codex-network/hosts}}"
  local ssh_config="${2:-${CODEX_NETWORK_SSH_CONFIG:-$HOME/.ssh/config}}"

  if [[ -n "${CODEX_NETWORK_SSH_HOSTS:-}" ]]; then
    printf '%s\n' "$CODEX_NETWORK_SSH_HOSTS" | tr ',' '\n' | awk '{ for (i = 1; i <= NF; i++) print $i }' | sort -u
    return 0
  fi

  if [[ -f "$hosts_file" ]]; then
    awk '
      $1 !~ /^#/ && $1 != "" {
        print $1
      }
    ' "$hosts_file" | sort -u
    return 0
  fi

  [[ -f "$ssh_config" ]] || return 0
  awk '
    $1 == "#" && ($0 ~ /BEGIN codex-network hosts/ || $0 ~ /BEGIN Codex RDE aliases/) { in_block = 1; next }
    $1 == "#" && ($0 ~ /END codex-network hosts/ || $0 ~ /END Codex RDE aliases/) { in_block = 0 }
    in_block && tolower($1) == "host" {
      for (i = 2; i <= NF; i++) {
        if ($i !~ /[*?]/) print $i
      }
    }
  ' "$ssh_config" | sort -u
}

validate_codex_network_host_alias() {
  [[ "$1" =~ ^[A-Za-z0-9_.@-]+$ ]]
}
