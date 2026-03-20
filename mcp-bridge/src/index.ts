import cors from "@fastify/cors";
import { createDatabase } from "./db/schema.js";
import { createDbClient } from "./db/client.js";
import { createEventBus } from "./application/events.js";
import { createMessageRoutes } from "./routes/messages.js";
import { createTaskRoutes } from "./routes/tasks.js";
import { createConversationRoutes } from "./routes/conversations.js";
import { registerSseRoute } from "./routes/events.js";
import { createServer } from "./server.js";

const PORT = parseInt(process.env["PORT"] ?? "3100", 10);
const HOST = process.env["HOST"] ?? "127.0.0.1";
const DB_PATH = process.env["DB_PATH"];

const LOOPBACK = new Set(["127.0.0.1", "::1", "localhost"]);
if (!LOOPBACK.has(HOST) && !process.env["ALLOW_REMOTE"]) {
  console.error(
    `Refusing to bind to ${HOST} — this server has no authentication.\n` +
    `Set ALLOW_REMOTE=1 to override (not recommended for untrusted networks).`,
  );
  process.exit(1);
}

async function main() {
  const database = createDatabase(DB_PATH);
  const db = createDbClient(database);
  const eventBus = createEventBus();

  const messageRoutes = createMessageRoutes(db, eventBus);
  const taskRoutes = createTaskRoutes(db, eventBus);
  const conversationRoutes = createConversationRoutes(db);

  const server = createServer([messageRoutes, taskRoutes, conversationRoutes]);

  // CORS — allow all origins (dev tool, no auth)
  await server.register(cors, { origin: true });

  // SSE — long-lived connections, outside normal route pattern
  registerSseRoute(server, eventBus);

  await server.listen({ port: PORT, host: HOST });

  console.log(`Bridge server running at http://${HOST}:${PORT}`);
  console.log(`SSE stream available at http://${HOST}:${PORT}/events`);
  console.log(`MCP server available via: node dist/mcp.js`);
}

main().catch((err) => {
  console.error("Server failed to start:", err);
  process.exit(1);
});
