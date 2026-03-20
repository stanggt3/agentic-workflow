# Dependency Graph

## Runtime Environment

| Requirement | Value |
|-------------|-------|
| Node.js | >= 20 |
| TypeScript target | ES2022 |
| Module system | Node16 (ESM — `"type": "module"` in package.json) |
| Module resolution | Node16 |
| Strict mode | Enabled |

## Runtime Dependencies

### MCP Bridge (`mcp-bridge/`)

| Package | Version | Purpose |
|---------|---------|---------|
| `@modelcontextprotocol/sdk` | ^1.12.1 | MCP server implementation — provides `McpServer` class and `StdioServerTransport` for exposing tools over the MCP stdio protocol |
| `better-sqlite3` | ^11.7.0 | Synchronous SQLite3 driver — used for the store-and-forward message queue and task persistence with WAL journal mode |
| `fastify` | ^5.2.1 | HTTP framework — serves the REST API on port 3100 with built-in logging |
| `@fastify/cors` | ^10.x | CORS plugin — enables cross-origin requests from the local UI dashboard at `:3000` |
| `zod` | ^3.24.2 | Schema validation — defines input/output shapes for both MCP tool parameters and REST API request bodies, params, and querystrings |

### UI Dashboard (`ui/`)

| Package | Purpose |
|---------|---------|
| `next` | Next.js 15 App Router — pages, routing, reverse proxy config |
| `react` / `react-dom` | React 19 — component rendering |
| `mermaid` | Diagram rendering — directed graphs and sequence diagrams |

## Dev Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `@types/better-sqlite3` | ^7.6.12 | TypeScript type definitions for better-sqlite3 |
| `@types/node` | ^22.10.0 | TypeScript type definitions for Node.js built-in modules |
| `tsx` | ^4.19.0 | TypeScript execution engine — runs `.ts` files directly for `npm run dev` without a build step |
| `typescript` | ^5.7.0 | TypeScript compiler — targets ES2022, emits declarations and source maps |
| `vitest` | ^2.1.9 | Test runner — configured for `vitest run` (single pass) and `vitest` (watch mode) |

## No Framework Lock-in

The project uses Fastify as a thin HTTP listener but does not depend on Fastify-specific features such as plugins, decorators, hooks, or serialization. The custom router in `server.ts` registers routes via a generic `ControllerDefinition` interface and performs Zod validation manually rather than using Fastify's schema validation. This means the HTTP layer could be swapped for any framework (Express, Hono, bare `node:http`) by reimplementing the ~90-line `createServer` function without touching application or domain logic.

## Layer Dependency Map

### MCP Bridge

```
Entry Points
├── index.ts (REST API)
│   ├── db/schema.ts .............. createDatabase()
│   ├── db/client.ts .............. createDbClient()
│   ├── application/events.ts ..... createEventBus()
│   ├── routes/messages.ts ........ createMessageRoutes(db, bus)
│   ├── routes/tasks.ts ........... createTaskRoutes(db, bus)
│   ├── routes/conversations.ts ... createConversationRoutes(db)
│   ├── routes/events.ts .......... registerEventsRoute(app, bus)
│   └── server.ts ................. createServer()
│
└── mcp.ts (MCP stdio server)
    ├── db/schema.ts .............. createDatabase()
    ├── db/client.ts .............. createDbClient()
    └── application/services/*.ts .. service functions directly

Routes Layer (routes/)
├── routes/messages.ts
│   ├── transport/controllers/message-controller.ts
│   ├── transport/types.ts ........ defineRoute, ControllerDefinition
│   └── transport/schemas/message-schemas.ts
│
├── routes/tasks.ts
│   ├── transport/controllers/task-controller.ts
│   ├── transport/types.ts ........ defineRoute, ControllerDefinition
│   └── transport/schemas/task-schemas.ts
│
├── routes/conversations.ts
│   ├── transport/controllers/conversation-controller.ts
│   ├── transport/types.ts ........ defineRoute, ControllerDefinition
│   └── transport/schemas/conversation-schemas.ts
│
└── routes/events.ts (SSE — bypasses defineRoute pattern)
    └── application/events.ts ..... EventBus, BridgeEvent

Transport Layer (transport/)
├── controllers/message-controller.ts
│   ├── application/services/send-context.ts
│   ├── application/services/get-messages.ts
│   ├── application/events.ts ..... EventBus (emit message:created)
│   └── transport/types.ts ........ ApiRequest, ApiResponse, appErr
│
├── controllers/task-controller.ts
│   ├── application/services/assign-task.ts
│   ├── application/services/report-status.ts
│   ├── application/events.ts ..... EventBus (emit task:created, task:updated)
│   ├── application/result.ts ..... ERROR_CODE
│   └── transport/types.ts ........ ApiRequest, ApiResponse, appErr
│
├── controllers/conversation-controller.ts
│   ├── application/services/get-conversations.ts
│   └── transport/types.ts ........ ApiRequest, ApiResponse, appErr
│
├── types.ts ...................... RouteSchema, RouteEntry, ControllerDefinition
│   └── zod (external) ........... ZodType
│
└── schemas/ ...................... Zod schema definitions (no internal deps)

Application Layer (application/)
├── result.ts ..................... AppResult<T>, ok(), err(), ERROR_CODE
├── events.ts ..................... EventBus, BridgeEvent, createEventBus()
│
├── services/send-context.ts
│   ├── db/client.ts .............. DbClient type
│   └── application/result.ts ..... AppResult, ok
│
├── services/get-messages.ts
│   ├── db/client.ts .............. DbClient type
│   └── application/result.ts ..... AppResult, ok
│
├── services/assign-task.ts
│   ├── db/client.ts .............. DbClient type
│   └── application/result.ts ..... AppResult, ok
│
├── services/report-status.ts
│   ├── db/client.ts .............. DbClient type
│   └── application/result.ts ..... AppResult, ok, err, ERROR_CODE
│
└── services/get-conversations.ts
    ├── db/client.ts .............. DbClient type (getConversations, getConversationCount)
    └── application/result.ts ..... AppResult, ok

Database Layer (db/)
├── schema.ts ..................... createDatabase(), MIGRATIONS SQL
│   └── better-sqlite3 (external)
│
└── client.ts ..................... DbClient interface, createDbClient()
    ├── better-sqlite3 (external) . Database type
    └── node:crypto ............... randomUUID()
```

### UI Dashboard

```
ui/src/
├── app/page.tsx
│   ├── lib/api.ts ................ fetchConversations()
│   └── hooks/use-sse.ts .......... useSSE() → EventSource /api/events
│
├── app/conversation/[id]/page.tsx
│   ├── lib/api.ts ................ fetchMessages(), fetchTasks()
│   ├── lib/diagrams.ts ........... buildDirectedGraph(), buildSequenceDiagram()
│   ├── components/timeline.tsx
│   └── components/diagram-renderer.tsx
│
├── lib/api.ts .................... fetch wrappers → /api/* (proxied to :3100)
├── lib/diagrams.ts ............... Mermaid definition builders (no external deps)
├── lib/types.ts .................. shared TypeScript types (Message, Task, ConversationSummary)
│
└── next.config.ts ................ rewrites /api/:path* → http://localhost:3100/:path*
```

## Dependency Direction

Dependencies flow strictly downward within the bridge:

```
  Entry Points (index.ts, mcp.ts)
         │
    Routes Layer (routes/)
         │
   Transport Layer (transport/)
         │
  Application Layer (application/)
         │
    Database Layer (db/)
         │
   External Packages + Node built-ins
```

No circular dependencies exist. The application layer never imports from the transport or routes layers. The database layer never imports from any layer above it. The MCP entry point bypasses the routes/transport layers entirely and calls service functions directly, which is why both transports (REST and MCP stdio) can coexist without coupling.

The EventBus (`application/events.ts`) is part of the application layer but is wired at the entry point level — it is injected into controllers as a dependency rather than imported directly by services. This keeps services pure (no side effects beyond the database).

The UI has no import relationship with the bridge codebase — it communicates exclusively over HTTP. The shared `lib/types.ts` in the UI mirrors bridge schemas manually; there is no generated client or shared package.

## External System Dependencies

| System | Binding | Required By |
|--------|---------|-------------|
| SQLite (via better-sqlite3) | File-based, default `./bridge.db` | MCP bridge data persistence |
| GitHub CLI (`gh`) | Shell command | Skills (review, postReview, addressReview) |
| Claude Code | CLI tool | Skills execution, MCP server registration |
| Node.js native modules | `node:crypto` (randomUUID), `node:path` (join) | db/client.ts, db/schema.ts |
| MCP Bridge REST API (`:3100`) | HTTP, localhost | UI dashboard (all data + SSE) |
