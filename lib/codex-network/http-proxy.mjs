import net from "node:net";
import process from "node:process";

function parsePortEnv(name) {
  const raw = process.env[name];
  const port = Number(raw);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`${name} must be a TCP port between 1 and 65535`);
  }
  return port;
}

function destroy(socket) {
  if (!socket.destroyed) socket.destroy();
}

function fail(error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}

function main() {
  const listenPort = parsePortEnv("LISTEN_PORT");
  const targetPort = parsePortEnv("TARGET_PORT");
  const targetHost = process.env.TARGET_HOST || "127.0.0.1";

  const server = net.createServer((client) => {
    const upstream = net.createConnection({ host: targetHost, port: targetPort });
    const closeBoth = () => {
      destroy(client);
      destroy(upstream);
    };

    client.on("error", closeBoth);
    upstream.on("error", closeBoth);
    client.pipe(upstream);
    upstream.pipe(client);
  });

  server.on("error", fail);
  server.listen({ host: "127.0.0.1", port: listenPort });
}

try {
  main();
} catch (error) {
  fail(error);
}
