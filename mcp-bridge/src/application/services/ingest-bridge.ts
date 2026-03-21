// mcp-bridge/src/application/services/ingest-bridge.ts
import type { MemoryDbClient, NodeRow } from "../../db/memory-client.js";
import type { DbClient, MessageRow, TaskRow } from "../../db/client.js";
import type { SecretFilter } from "../../ingestion/secret-filter.js";
import type { AppResult } from "../result.js";
import { ok } from "../result.js";

// ── P1: Repo slug normalization ──────────────────────────────

export function normalizeRepoSlug(urlOrPath: string): string {
  const sshMatch = urlOrPath.match(/git@[^:]+:(.+?)(?:\.git)?$/);
  if (sshMatch) return sshMatch[1].replace(/\//g, "-");

  try {
    const url = new URL(urlOrPath);
    const path = url.pathname.replace(/^\//, "").replace(/\.git$/, "");
    return path.replace(/\//g, "-");
  } catch {
    const segments = urlOrPath.replace(/\/+$/, "").split("/");
    return segments[segments.length - 1];
  }
}

// ── Helpers ──────────────────────────────────────────────────

function ensureConversationNode(
  mdb: MemoryDbClient,
  repo: string,
  conversationId: string,
): NodeRow {
  const existing = mdb.getNodeBySource("bridge-conversation", conversationId);
  if (existing) return existing;

  return mdb.insertNode({
    repo,
    kind: "conversation",
    title: `Conversation ${conversationId.slice(0, 8)}`,
    body: "",
    meta: JSON.stringify({ conversation_id: conversationId }),
    source_id: conversationId,
    source_type: "bridge-conversation",
  });
}

// ── Ingest a single bridge message ───────────────────────────

export function ingestBridgeMessage(
  mdb: MemoryDbClient,
  filter: SecretFilter,
  repo: string,
  message: MessageRow,
): AppResult<NodeRow> {
  const existing = mdb.getNodeBySource("bridge", message.id);
  if (existing) return ok(existing);

  const node = mdb.transaction(() => {
    const convNode = ensureConversationNode(mdb, repo, message.conversation);

    const msgNode = mdb.insertNode({
      repo,
      kind: "message",
      title: filter.redact(message.payload.slice(0, 120)),
      body: filter.redact(message.payload),
      meta: JSON.stringify({
        sender: message.sender,
        recipient: message.recipient,
        kind: message.kind,
      }),
      source_id: message.id,
      source_type: "bridge",
    });

    mdb.insertEdge({
      repo,
      from_node: convNode.id,
      to_node: msgNode.id,
      kind: "contains",
      weight: 1.0,
      meta: "{}",
      auto: true,
    });

    return msgNode;
  });

  return ok(node);
}

// ── Ingest a single bridge task ──────────────────────────────

export function ingestBridgeTask(
  mdb: MemoryDbClient,
  filter: SecretFilter,
  repo: string,
  task: TaskRow,
): AppResult<NodeRow> {
  const existing = mdb.getNodeBySource("bridge-task", task.id);
  if (existing) return ok(existing);

  const node = mdb.transaction(() => {
    const convNode = ensureConversationNode(mdb, repo, task.conversation);

    const taskNode = mdb.insertNode({
      repo,
      kind: "task",
      title: filter.redact(task.summary),
      body: filter.redact(task.details),
      meta: JSON.stringify({
        domain: task.domain,
        status: task.status,
        assigned_to: task.assigned_to,
      }),
      source_id: task.id,
      source_type: "bridge-task",
    });

    mdb.insertEdge({
      repo,
      from_node: convNode.id,
      to_node: taskNode.id,
      kind: "spawned",
      weight: 1.0,
      meta: "{}",
      auto: true,
    });

    return taskNode;
  });

  return ok(node);
}

// ── Backfill all existing bridge data ────────────────────────

export interface BackfillResult {
  messages_ingested: number;
  tasks_ingested: number;
}

const BACKFILL_BATCH_SIZE = 100;

function yieldToEventLoop(): Promise<void> {
  return new Promise((resolve) => setImmediate(resolve));
}

export async function backfillBridge(
  mdb: MemoryDbClient,
  bridgeDb: DbClient,
  filter: SecretFilter,
  repo: string,
): Promise<AppResult<BackfillResult>> {
  const conversations = bridgeDb.getConversations(10000, 0);
  let messagesIngested = 0;
  let tasksIngested = 0;

  for (let i = 0; i < conversations.length; i++) {
    const conv = conversations[i];

    const messages = bridgeDb.getMessagesByConversation(conv.conversation);
    for (const msg of messages) {
      const result = ingestBridgeMessage(mdb, filter, repo, msg);
      if (result.ok) messagesIngested++;
    }

    const tasks = bridgeDb.getTasksByConversation(conv.conversation);
    for (const task of tasks) {
      const result = ingestBridgeTask(mdb, filter, repo, task);
      if (result.ok) tasksIngested++;
    }

    // Yield to event loop every BACKFILL_BATCH_SIZE conversations
    if ((i + 1) % BACKFILL_BATCH_SIZE === 0) {
      await yieldToEventLoop();
    }
  }

  mdb.upsertCursor("bridge-backfill", repo, new Date().toISOString());

  return ok({ messages_ingested: messagesIngested, tasks_ingested: tasksIngested });
}
