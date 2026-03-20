import { ok, type AppResult } from "../result.js";
import type { DbClient, ConversationSummary } from "../../db/client.js";

export interface GetConversationsInput {
  limit: number;
  offset: number;
}

export interface GetConversationsOutput {
  conversations: ConversationSummary[];
  total: number;
}

export function getConversations(
  db: DbClient,
  input: GetConversationsInput,
): AppResult<GetConversationsOutput> {
  const conversations = db.getConversations(input.limit, input.offset);
  const total = db.getConversationCount();
  return ok({ conversations, total });
}
