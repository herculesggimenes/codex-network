#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

port_open_local() {
  local port="$1"
  (exec 3<>"/dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1
}

pick_available_port() {
  local port="$1"
  local end=$((port + 99))
  while ((port <= end)); do
    if ! port_open_local "$port"; then
      printf '%s\n' "$port"
      return
    fi
    port=$((port + 1))
  done
  echo "unable to find an available local port" >&2
  return 1
}

wait_for_local_port() {
  local port="$1"
  for _attempt in 1 2 3 4 5 6 7 8 9 10; do
    port_open_local "$port" && return 0
    sleep 0.2
  done
  return 1
}

check_http_proxy() (
  set -euo pipefail
  local origin_port listen_port server_pid proxy_pid
  origin_port="$(pick_available_port 49531)"
  listen_port="$(pick_available_port "$((origin_port + 1))")"
  server_pid=""
  proxy_pid=""

  trap '[[ -n "$proxy_pid" ]] && kill "$proxy_pid" 2>/dev/null || true; [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true; [[ -n "$proxy_pid" ]] && wait "$proxy_pid" 2>/dev/null || true; [[ -n "$server_pid" ]] && wait "$server_pid" 2>/dev/null || true' EXIT

  PORT="$origin_port" node --input-type=module <<'NODE' &
import http from "node:http";

const port = Number(process.env.PORT);
http
  .createServer((_request, response) => {
    response.end("codex-network-proxy-ok\n");
  })
  .listen({ host: "127.0.0.1", port });
NODE
  server_pid=$!
  wait_for_local_port "$origin_port"

  LISTEN_PORT="$listen_port" TARGET_HOST=127.0.0.1 TARGET_PORT="$origin_port" node lib/codex-network/http-proxy.mjs &
  proxy_pid=$!

  for _attempt in 1 2 3 4 5 6 7 8 9 10; do
    if PROXY_URL="http://127.0.0.1:${listen_port}" node --input-type=module 2>/dev/null <<'NODE'
const response = await fetch(process.env.PROXY_URL);
const body = await response.text();
if (body.trim() !== "codex-network-proxy-ok") process.exit(1);
NODE
    then
      return 0
    fi
    sleep 0.2
  done
  return 1
)

check_control_server() (
  set -euo pipefail
  local tmp_dir fake_bin control_port server_pid output
  tmp_dir="$(mktemp -d)"
  fake_bin="$tmp_dir/codex-network"
  control_port="$(pick_available_port 49631)"
  server_pid=""
  trap '[[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true; [[ -n "$server_pid" ]] && wait "$server_pid" 2>/dev/null || true; rm -rf "$tmp_dir"' EXIT

  cat > "$fake_bin" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf 'args:%s\n' "$*"
FAKE
  chmod +x "$fake_bin"
  mkdir -p "$tmp_dir/home/.codex-network"
  printf 'remote-a\n' > "$tmp_dir/home/.codex-network/node"

  CODEX_NETWORK_BIN="$fake_bin" CODEX_NETWORK_CONTROL_PORT="$control_port" node lib/codex-network/control-server.mjs &
  server_pid=$!
  wait_for_local_port "$control_port"

  output="$(
    HOME="$tmp_dir/home" \
      CODEX_NETWORK_HOSTS_FILE="$tmp_dir/missing-hosts" \
      CODEX_NETWORK_SSH_CONFIG="$tmp_dir/missing-ssh-config" \
      CODEX_NETWORK_CONTROL_URL="http://127.0.0.1:${control_port}" \
      bin/codex-network http expose --port 3000 --name demo
  )"
  [[ "$output" == "args:__http-expose-parent --default-node remote-a --port 3000 --name demo" ]]

  output="$(
    HOME="$tmp_dir/home" \
      CODEX_NETWORK_HOSTS_FILE="$tmp_dir/missing-hosts" \
      CODEX_NETWORK_SSH_CONFIG="$tmp_dir/missing-ssh-config" \
      CODEX_NETWORK_CONTROL_URL="http://127.0.0.1:${control_port}" \
      bin/codex-network http stop demo
  )"
  [[ "$output" == "args:__http-stop-parent demo" ]]

  output="$(
    HOME="$tmp_dir/home" \
      CODEX_NETWORK_HOSTS_FILE="$tmp_dir/missing-hosts" \
      CODEX_NETWORK_SSH_CONFIG="$tmp_dir/missing-ssh-config" \
      CODEX_NETWORK_CONTROL_URL="http://127.0.0.1:${control_port}" \
      bin/codex-network open "https://example.com/oauth?state=demo"
  )"
  [[ "$output" == "args:__browser-open-parent https://example.com/oauth?state=demo" ]]
)

check_browser_open() (
  set -euo pipefail
  local tmp_dir fake_open output
  tmp_dir="$(mktemp -d)"
  fake_open="$tmp_dir/open-browser"
  trap 'rm -rf "$tmp_dir"' EXIT

  cat > "$fake_open" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "${FAKE_BROWSER_LOG:?}"
FAKE
  chmod +x "$fake_open"

  output="$(
    CODEX_NETWORK_BROWSER_OPEN_CMD="$fake_open" \
      FAKE_BROWSER_LOG="$tmp_dir/browser.log" \
      CODEX_NETWORK_CONTROL_DISABLE=1 \
      bin/codex-network open "http://127.0.0.1:3000/path"
  )"
  [[ "$output" == "opened browser URL: http://127.0.0.1:3000/path" ]]
  grep -qx 'http://127.0.0.1:3000/path' "$tmp_dir/browser.log"

  mkdir -p "$tmp_dir/home/.codex-network"
  printf 'demo\tlocal\t3000\t3000\thttp://127.0.0.1:3000\n' > "$tmp_dir/home/.codex-network/http.tsv"
  output="$(
    HOME="$tmp_dir/home" \
      CODEX_NETWORK_BROWSER_OPEN_CMD="$fake_open" \
      FAKE_BROWSER_LOG="$tmp_dir/browser.log" \
      CODEX_NETWORK_CONTROL_DISABLE=1 \
      bin/codex-network open demo
  )"
  [[ "$output" == "opened browser URL: http://127.0.0.1:3000" ]]
  grep -qx 'http://127.0.0.1:3000' "$tmp_dir/browser.log"

  if CODEX_NETWORK_BROWSER_OPEN_CMD="$fake_open" FAKE_BROWSER_LOG="$tmp_dir/browser.log" bin/codex-network open "file:///tmp/nope" >/dev/null 2>&1; then
    return 1
  fi
)

check_conversation_doctor() (
  set -euo pipefail
  local tmp_dir fake_lib output
  tmp_dir="$(mktemp -d)"
  fake_lib="$tmp_dir/lib"
  mkdir -p "$fake_lib"
  trap 'rm -rf "$tmp_dir"' EXIT

  cp lib/codex-network/hosts.bash "$fake_lib/hosts.bash"
  cat > "$fake_lib/rpc.mjs" <<'NODE'
const command = process.argv[2];
const node = process.env.CODEX_NETWORK_NODE || "local";
if (command === "list") {
  console.log(`${node}\t${node}-thread\t2026-01-01T00:00:00Z\tidle\t/workspaces/${node}\t${node} title`);
} else if (command === "resolve") {
  const id = process.env.CODEX_NETWORK_CONVERSATION_ID;
  const expected = `${node}-thread`;
  if (id !== expected) process.exit(1);
  console.log(`${node}\t${expected}\t2026-01-01T00:00:00Z\t/workspaces/${node}\t${node} title`);
} else {
  process.exit(1);
}
NODE

  output="$(
    CODEX_NETWORK_LIB_DIR="$fake_lib" \
      CODEX_NETWORK_SKIP_READY_CHECK=1 \
      CODEX_NETWORK_NODES_FILE="$tmp_dir/nodes.tsv" \
      CODEX_NETWORK_HOSTS_FILE="$tmp_dir/missing-hosts" \
      CODEX_NETWORK_SSH_CONFIG="$tmp_dir/missing-ssh-config" \
      bin/codex-network doctor conversations --limit 5
  )"
  grep -q 'checked=0' <<< "$output" && return 1
  grep -q 'failed=0' <<< "$output"
  grep -q '/workspaces/local' <<< "$output"

  printf 'local\tws://127.0.0.1:1\nremote-a\tws://127.0.0.1:2\n' > "$tmp_dir/nodes.tsv"
  output="$(
    CODEX_NETWORK_LIB_DIR="$fake_lib" \
      CODEX_NETWORK_SKIP_READY_CHECK=1 \
      CODEX_NETWORK_NODES_FILE="$tmp_dir/nodes.tsv" \
      CODEX_NETWORK_HOSTS_FILE="$tmp_dir/missing-hosts" \
      CODEX_NETWORK_SSH_CONFIG="$tmp_dir/missing-ssh-config" \
      bin/codex-network doctor conversations --limit 5
  )"
  grep -q 'checked=2 failed=0' <<< "$output"
  grep -q '/workspaces/local' <<< "$output"
  grep -q '/workspaces/remote-a' <<< "$output"
)

check_stale_app_server_session_restart() (
  set -euo pipefail
  local tmp_dir fake_bin log output
  tmp_dir="$(mktemp -d)"
  fake_bin="$tmp_dir/bin"
  log="$tmp_dir/tmux.log"
  mkdir -p "$fake_bin"
  trap 'rm -rf "$tmp_dir"' EXIT

  cat > "$fake_bin/codex" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
  cat > "$fake_bin/curl" <<'FAKE'
#!/usr/bin/env bash
[[ "${FAKE_CURL_READY:-0}" == "1" ]]
FAKE
  cat > "$fake_bin/node" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
  cat > "$fake_bin/tmux" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-L" ]]; then
  shift 2
fi
case "${1:-}" in
  has-session)
    [[ ! -f "${FAKE_TMUX_KILLED:?}" ]]
    ;;
  kill-session)
    touch "${FAKE_TMUX_KILLED:?}"
    printf 'kill %s\n' "$*" >> "${FAKE_TMUX_LOG:?}"
    ;;
  new-session)
    rm -f "${FAKE_TMUX_KILLED:?}"
    printf 'new %s\n' "$*" >> "${FAKE_TMUX_LOG:?}"
    ;;
  *)
    exit 1
    ;;
esac
FAKE
  chmod +x "$fake_bin/codex" "$fake_bin/curl" "$fake_bin/node" "$fake_bin/tmux"

  output="$(PATH="$fake_bin:$PATH" FAKE_TMUX_KILLED="$tmp_dir/tmux-killed" FAKE_TMUX_LOG="$log" bin/codex-network serve --url ws://127.0.0.1:49999 2>&1)"
  grep -q 'restarting stale codex app-server tmux session' <<< "$output"
  grep -q '^kill ' "$log"
  grep -q '^new ' "$log"

  : > "$log"
  rm -f "$tmp_dir/tmux-killed"
  output="$(PATH="$fake_bin:$PATH" FAKE_CURL_READY=1 FAKE_TMUX_KILLED="$tmp_dir/tmux-killed" FAKE_TMUX_LOG="$log" bin/codex-network serve --url ws://127.0.0.1:49999 2>&1)"
  grep -q 'codex app-server already running' <<< "$output"
  [[ ! -s "$log" ]]

  : > "$log"
  rm -f "$tmp_dir/tmux-killed"
  output="$(PATH="$fake_bin:$PATH" FAKE_TMUX_KILLED="$tmp_dir/tmux-killed" FAKE_TMUX_LOG="$log" bin/codex-network control serve --port 49998 2>&1)"
  grep -q 'restarting stale control server tmux session' <<< "$output"
  grep -q '^kill ' "$log"
  grep -q '^new ' "$log"
)

echo "checking shell syntax"
bash -n bin/codex-network install.sh scripts/sync-remotes.sh scripts/sync-rdes.sh lib/codex-network/hosts.bash
echo "checking Node helper syntax"
for script in eslint.config.mjs lib/codex-network/*.mjs; do
  node --check "$script"
done
echo "checking Node WebSocket runtime"
node -e 'if (!globalThis.WebSocket) process.exit(1)'
echo "checking linters"
npm run lint
echo "checking formatting"
npm run format:check
echo "checking dependency audit"
npm audit --audit-level=moderate
echo "checking HTTP proxy helper"
check_http_proxy
echo "checking parent control helper"
check_control_server
echo "checking browser open helper"
check_browser_open
echo "checking conversation id doctor"
check_conversation_doctor
echo "checking stale app-server session restart"
check_stale_app_server_session_restart
echo "checking CLI smoke paths"
bin/codex-network --help >/dev/null
bin/codex-network http list >/dev/null

echo "checking host discovery"
actual="$(
  CODEX_NETWORK_SSH_HOSTS='beta,alpha alpha' bash -c '
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
test -f "$tmp_home/.local/lib/codex-network/http-proxy.mjs"
test -f "$tmp_home/.local/lib/codex-network/control-client.mjs"
test -f "$tmp_home/.local/lib/codex-network/control-server.mjs"
test -f "$tmp_home/.agents/skills/codex-network/SKILL.md"
