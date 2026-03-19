import type { DbClient } from "../../db/client.js";
import type { AppResult } from "../result.js";
import { ok, err, ERROR_CODE } from "../result.js";

export interface ReportStatusInput {
  conversation: string;
  sender: string;
  recipient: string;
  task_id?: string;
  status: "in_progress" | "completed" | "failed";
  payload: string;
}

export interface ReportStatusResult {
  message_id: string;
  task_updated: boolean;
}

export function reportStatus(
  db: DbClient,
  input: ReportStatusInput,
): AppResult<ReportStatusResult> {
  // Validate task existence before any writes
  if (input.task_id) {
    const task = db.getTask(input.task_id);
    if (!task) {
      return err({
        code: ERROR_CODE.notFound,
        message: `Task ${input.task_id} not found`,
        statusHint: 404,
      });
    }
  }

  // Wrap both operations in a transaction for atomicity
  const result = db.transaction(() => {
    const msg = db.insertMessage({
      conversation: input.conversation,
      sender: input.sender,
      recipient: input.recipient,
      kind: "status",
      payload: input.payload,
      meta_prompt: null,
    });

    let taskUpdated = false;
    if (input.task_id) {
      db.updateTaskStatus(input.task_id, input.status, input.payload);
      taskUpdated = true;
    }

    return { message_id: msg.id, task_updated: taskUpdated };
  });

  return ok(result);
}
