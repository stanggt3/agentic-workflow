import type { DbClient, MessageRow } from "../../db/client.js";
import type { AppResult } from "../result.js";
import { ok } from "../result.js";

export function getMessagesByConversation(
  db: DbClient,
  conversation: string,
): AppResult<MessageRow[]> {
  const rows = db.getMessagesByConversation(conversation);
  return ok(rows);
}

export function getUnreadMessages(
  db: DbClient,
  recipient: string,
): AppResult<MessageRow[]> {
  // Atomic: fetch unread then bulk mark-read in a transaction
  const rows = db.transaction(() => {
    const unread = db.getUnreadMessages(recipient);
    if (unread.length > 0) {
      db.markAllRead(recipient);
    }
    return unread;
  });
  return ok(rows);
}
