import { spawn } from "node:child_process";
import http from "node:http";
import process from "node:process";

const MAX_BODY_BYTES = 64 * 1024;
const ROUTES = new Map([
  ["/host/bash", "host-bash"],
  ["/http/expose", "http-expose"],
  ["/http/stop", "http-stop"],
  ["/open", "open-url"],
]);

function parsePortEnv(name, fallback) {
  const raw = process.env[name] || String(fallback);
  const port = Number(raw);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`${name} must be a TCP port between 1 and 65535`);
  }
  return port;
}

function fail(error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}

function sendJson(response, statusCode, body) {
  const payload = JSON.stringify(body);
  response.writeHead(statusCode, {
    "content-type": "application/json",
    "content-length": Buffer.byteLength(payload),
  });
  response.end(payload);
}

function readJson(request) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];

    request.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(new Error("request body is too large"));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on("error", reject);
    request.on("end", () => {
      try {
        const body = Buffer.concat(chunks).toString("utf8");
        resolve(body ? JSON.parse(body) : {});
      } catch (error) {
        reject(error);
      }
    });
  });
}

function validateStringArray(value, name) {
  if (!Array.isArray(value)) throw new Error(`${name} must be an array`);
  if (value.length > 128) throw new Error(`${name} is too large`);
  for (const item of value) {
    if (typeof item !== "string") throw new Error(`${name} must contain only strings`);
    if (item.length > 4096) throw new Error(`${name} contains an item that is too large`);
  }
  return value;
}

function commandFor(action, body) {
  const args = validateStringArray(body.args || [], "args");
  if (action === "host-bash") return ["__host-bash-parent", ...args];
  if (action === "http-expose") {
    const command = ["__http-expose-parent"];
    if (body.defaultNode) {
      if (typeof body.defaultNode !== "string") throw new Error("defaultNode must be a string");
      command.push("--default-node", body.defaultNode);
    }
    command.push(...args);
    return command;
  }
  if (action === "http-stop") return ["__http-stop-parent", ...args];
  if (action === "open-url") return ["__open-url-parent", ...args];
  throw new Error(`unsupported action: ${action}`);
}

function runCodexNetwork(args) {
  const bin = process.env.CODEX_NETWORK_BIN;
  if (!bin) throw new Error("CODEX_NETWORK_BIN is required");

  return new Promise((resolve) => {
    const child = spawn(bin, args, {
      env: { ...process.env, CODEX_NETWORK_CONTROL_DISABLE: "1" },
      stdio: ["ignore", "pipe", "pipe"],
    });
    const stdout = [];
    const stderr = [];

    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", (error) => {
      resolve({ ok: false, exitCode: 1, stdout: "", stderr: `${error.message}\n` });
    });
    child.on("close", (code) => {
      resolve({
        ok: code === 0,
        exitCode: code || 0,
        stdout: Buffer.concat(stdout).toString("utf8"),
        stderr: Buffer.concat(stderr).toString("utf8"),
      });
    });
  });
}

async function handleRequest(request, response) {
  const url = new URL(request.url || "/", "http://127.0.0.1");
  if (request.method === "GET" && url.pathname === "/readyz") {
    response.writeHead(204);
    response.end();
    return;
  }

  const action = ROUTES.get(url.pathname);
  if (request.method !== "POST" || !action) {
    sendJson(response, 404, { ok: false, exitCode: 1, stderr: "not found\n" });
    return;
  }

  try {
    const body = await readJson(request);
    const result = await runCodexNetwork(commandFor(action, body));
    sendJson(response, result.ok ? 200 : 409, result);
  } catch (error) {
    sendJson(response, 400, {
      ok: false,
      exitCode: 1,
      stdout: "",
      stderr: `${error instanceof Error ? error.message : String(error)}\n`,
    });
  }
}

try {
  const port = parsePortEnv("CODEX_NETWORK_CONTROL_PORT", 49323);
  const server = http.createServer((request, response) => {
    handleRequest(request, response).catch((error) => {
      sendJson(response, 500, {
        ok: false,
        exitCode: 1,
        stdout: "",
        stderr: `${error instanceof Error ? error.message : String(error)}\n`,
      });
    });
  });
  server.on("error", fail);
  server.listen({ host: "127.0.0.1", port });
} catch (error) {
  fail(error);
}
