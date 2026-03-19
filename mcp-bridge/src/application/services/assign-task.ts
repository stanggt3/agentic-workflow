import type { DbClient, TaskRow } from "../../db/client.js";
import type { AppResult } from "../result.js";
import { ok } from "../result.js";

export interface AssignTaskInput {
  conversation: string;
  domain: string;
  summary: string;
  details: string;
  analysis?: string;
  assigned_to?: string;
}

export function assignTask(db: DbClient, input: AssignTaskInput): AppResult<TaskRow> {
  // Wrap task + message insertion in a transaction for atomicity
  const row = db.transaction(() => {
    const task = db.insertTask({
      conversation: input.conversation,
      domain: input.domain,
      summary: input.summary,
      details: input.details,
      analysis: input.analysis ?? null,
      assigned_to: input.assigned_to ?? null,
    });

    db.insertMessage({
      conversation: input.conversation,
      sender: "system",
      recipient: input.assigned_to ?? "unassigned",
      kind: "task",
      payload: JSON.stringify({
        task_id: task.id,
        domain: input.domain,
        summary: input.summary,
        details: input.details,
      }),
      meta_prompt: null,
    });

    return task;
  });

  return ok(row);
}
