const command = process.argv[2];
const CLIENT_INFO = { name: "codex-network", title: "Codex Network", version: "0.1.0" };

function env(name, fallback = "") {
  return process.env[name] ?? fallback;
}

function fail(error) {
  const message = process.env.CODEX_NETWORK_DEBUG && error && error.stack
    ? error.stack
    : error && error.message
      ? error.message
      : String(error);
  console.error(message);
  process.exit(1);
}

function field(value) {
  return String(value ?? "").replace(/\t/g, " ").replace(/\r?\n/g, " ");
}

function titleOf(thread) {
  const title = thread?.name || thread?.preview || "";
  return title.replace(/\s+/g, " ").trim();
}

function statusOf(thread) {
  const status = thread?.status;
  if (typeof status === "string") return status;
  if (status && typeof status.type === "string") return status.type;
  return "";
}

function isoTime(seconds) {
  if (!Number.isFinite(seconds)) return "";
  return new Date(seconds * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");
}

function itemText(item) {
  if (!item || typeof item !== "object") return null;
  if (item.type === "agentMessage" && typeof item.text === "string") return item.text;
  if (item.type === "reasoning" && typeof item.text === "string") return item.text;
  if (typeof item.text === "string" && (item.type || "").toLowerCase().includes("agent")) return item.text;
  return null;
}

class CodexRpcClient {
  constructor(url, { timeoutMs = 15000, capabilities = {} } = {}) {
    this.url = url;
    this.timeoutMs = timeoutMs;
    this.capabilities = capabilities;
    this.nextId = 1;
    this.pending = new Map();
    this.ws = null;
    this.timeout = null;
    this.closing = false;
  }

  async connect() {
    if (this.timeoutMs > 0) {
      this.timeout = setTimeout(() => fail(`Codex RPC timed out after ${this.timeoutMs}ms`), this.timeoutMs);
    }
    this.ws = new WebSocket(this.url);
    this.ws.addEventListener("message", (event) => this.handleMessage(event));
    this.ws.addEventListener("error", (event) => {
      if (this.closing) return;
      fail(event.error || "websocket error");
    });
    await new Promise((resolve, reject) => {
      this.ws.addEventListener("open", resolve, { once: true });
      this.ws.addEventListener("error", (event) => reject(event.error || new Error("websocket error")), { once: true });
    });
    await this.initialize();
  }

  async initialize() {
    await this.request("initialize", {
      clientInfo: CLIENT_INFO,
      capabilities: {
        experimentalApi: true,
        ...this.capabilities,
      },
    });
    this.notify("initialized", null);
  }

  request(method, params) {
    const id = this.nextId++;
    const promise = new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject, method });
    });
    this.ws.send(JSON.stringify({ jsonrpc: "2.0", id, method, params }));
    return promise;
  }

  notify(method, params) {
    this.ws.send(JSON.stringify({ jsonrpc: "2.0", method, params }));
  }

  handleMessage(event) {
    let msg;
    try {
      msg = JSON.parse(event.data);
    } catch {
      return;
    }
    if (!Object.prototype.hasOwnProperty.call(msg, "id") || !this.pending.has(msg.id)) return;
    const { resolve, reject, method } = this.pending.get(msg.id);
    this.pending.delete(msg.id);
    if (msg.error) reject(new Error(`${method} failed: ${JSON.stringify(msg.error)}`));
    else resolve(msg.result);
  }

  close() {
    this.closing = true;
    if (this.timeout) clearTimeout(this.timeout);
    if (this.ws && this.ws.readyState < WebSocket.CLOSING) this.ws.close();
  }
}

async function listThreads() {
  const url = env("CODEX_NETWORK_URL");
  const nodeName = env("CODEX_NETWORK_NODE", "local");
  const limit = Number.parseInt(env("CODEX_NETWORK_LIMIT", "20"), 10);
  const search = env("CODEX_NETWORK_SEARCH");
  const client = new CodexRpcClient(url);
  await client.connect();
  try {
    const result = await client.request("thread/list", {
      limit,
      sortKey: "updated_at",
      sortDirection: "desc",
      archived: false,
      useStateDbOnly: false,
      searchTerm: search || null,
    });

    for (const thread of result?.data || []) {
      console.log([
        nodeName,
        thread.id,
        isoTime(thread.updatedAt),
        statusOf(thread),
        thread.cwd || "",
        titleOf(thread),
      ].map(field).join("\t"));
    }
  } finally {
    client.close();
  }
}

function threadMatches(thread, needle) {
  return thread?.id === needle ||
    thread?.sessionId === needle ||
    String(thread?.id || "").startsWith(needle) ||
    String(thread?.sessionId || "").startsWith(needle);
}

function printMatch(nodeName, thread) {
  console.log([
    nodeName,
    thread.id,
    isoTime(thread.updatedAt),
    thread.cwd || "",
    titleOf(thread),
  ].map(field).join("\t"));
}

async function resolveThread() {
  const url = env("CODEX_NETWORK_URL");
  const nodeName = env("CODEX_NETWORK_NODE", "local");
  const needle = env("CODEX_NETWORK_CONVERSATION_ID");
  const maxScan = Number.parseInt(env("CODEX_NETWORK_MAX_SCAN", "2000"), 10);
  const client = new CodexRpcClient(url, { timeoutMs: 20000 });
  await client.connect();
  try {
    let cursor = null;
    let scanned = 0;
    const matches = [];
    while (scanned < maxScan) {
      const pageLimit = Math.min(100, maxScan - scanned);
      const result = await client.request("thread/list", {
        cursor,
        limit: pageLimit,
        sortKey: "updated_at",
        sortDirection: "desc",
        archived: false,
        useStateDbOnly: false,
      });
      const data = result?.data || [];
      for (const thread of data) {
        if (threadMatches(thread, needle)) matches.push(thread);
      }
      scanned += data.length;
      if (!result?.nextCursor || data.length === 0) break;
      cursor = result.nextCursor;
    }

    if (matches.length === 0 && /^[0-9a-fA-F-]{36}$/.test(needle)) {
      try {
        const read = await client.request("thread/read", { threadId: needle, includeTurns: false });
        if (read?.thread) matches.push(read.thread);
      } catch {
        // Missing exact threads are normal while scanning multiple nodes.
      }
    }

    for (const thread of matches) printMatch(nodeName, thread);
    process.exitCode = matches.length > 0 ? 0 : 1;
  } finally {
    client.close();
  }
}

async function sendMessage() {
  const url = env("CODEX_NETWORK_URL");
  const threadId = env("CODEX_NETWORK_THREAD_ID");
  const cwd = env("CODEX_NETWORK_CWD");
  const message = env("CODEX_NETWORK_MESSAGE");
  let targetTurnId = null;
  let completed = false;

  const client = new CodexRpcClient(url, {
    timeoutMs: Number.parseInt(env("CODEX_NETWORK_SEND_TIMEOUT_MS", "0"), 10),
    capabilities: {
      optOutNotificationMethods: [
        "item/reasoning_text/delta",
        "item/reasoning_summary_text/delta",
      ],
    },
  });
  await client.connect();
  client.ws.addEventListener("message", (event) => {
    let msg;
    try {
      msg = JSON.parse(event.data);
    } catch {
      console.error(`invalid JSON from app-server: ${event.data}`);
      return;
    }

    if (!msg.method) return;
    const params = msg.params || {};
    if (msg.method === "item/completed") {
      const text = itemText(params.item);
      if (text) process.stdout.write(`${text}\n`);
    }
    if (msg.method === "turn/completed" && params.turn?.id === targetTurnId) {
      completed = true;
      const status = params.turn?.status || "unknown";
      console.error(`completed: ${status}`);
      if (status === "failed" && params.turn?.error?.message) {
        console.error(params.turn.error.message);
        process.exitCode = 1;
      }
      client.close();
    }
  });
  client.ws.addEventListener("close", () => {
    if (!completed && targetTurnId) {
      console.error("connection closed before turn/completed");
      process.exit(1);
    }
  });

  const resumeParams = { threadId };
  if (cwd) resumeParams.cwd = cwd;
  const resume = await client.request("thread/resume", resumeParams);
  const resolvedThreadId = resume?.thread?.id || threadId;
  const activeTurn = Array.isArray(resume?.thread?.turns)
    ? [...resume.thread.turns].reverse().find((turn) => turn?.status === "inProgress")
    : null;

  const input = [{ type: "text", text: message, textElements: [] }];
  if (activeTurn?.id) {
    const steer = await client.request("turn/steer", {
      threadId: resolvedThreadId,
      expectedTurnId: activeTurn.id,
      input,
    });
    targetTurnId = steer?.turnId || activeTurn.id;
    console.error(`steered: thread=${resolvedThreadId} turn=${targetTurnId}`);
    return;
  }

  const turn = await client.request("turn/start", { threadId: resolvedThreadId, input });
  targetTurnId = turn?.turn?.id;
  if (!targetTurnId) {
    throw new Error(`turn/start response did not include turn.id: ${JSON.stringify(turn)}`);
  }
  console.error(`sent: thread=${resolvedThreadId} turn=${targetTurnId}`);
}

try {
  if (!globalThis.WebSocket) {
    throw new Error("Node.js global WebSocket support is required");
  }

  if (command === "list") await listThreads();
  else if (command === "resolve") await resolveThread();
  else if (command === "send") await sendMessage();
  else throw new Error(`unknown RPC command: ${command || ""}`);
} catch (error) {
  fail(error);
}
