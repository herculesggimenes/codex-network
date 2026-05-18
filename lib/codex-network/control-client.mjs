import process from "node:process";

const ENDPOINTS = new Map([
  ["http-expose", "/http/expose"],
  ["http-stop", "/http/stop"],
]);

function fail(message) {
  console.error(message);
  process.exit(1);
}

function resolveUrl(path) {
  const base = process.env.CODEX_NETWORK_CONTROL_URL || "http://127.0.0.1:49323";
  return new URL(path, base.endsWith("/") ? base : `${base}/`);
}

const [action, ...args] = process.argv.slice(2);
const endpoint = ENDPOINTS.get(action);
if (!endpoint) {
  fail(`unknown control action: ${action || ""}`);
}

let result;
try {
  const response = await fetch(resolveUrl(endpoint), {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      args,
      defaultNode: process.env.CODEX_NETWORK_CONTROL_DEFAULT_NODE || "",
    }),
  });
  result = await response.json();
  if (!response.ok) {
    process.exitCode = result.exitCode || 1;
  }
} catch {
  const controlUrl = process.env.CODEX_NETWORK_CONTROL_URL || "http://127.0.0.1:49323";
  fail(
    `unable to reach parent control server at ${controlUrl}; run codex-network expose-parent --all-hosts on the parent node`,
  );
}

if (result.stderr) process.stderr.write(result.stderr);
if (result.stdout) process.stdout.write(result.stdout);

if (result.ok === false) {
  process.exit(result.exitCode || 1);
}
