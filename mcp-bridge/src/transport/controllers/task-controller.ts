import type { DbClient } from "../../db/client.js";
import type { EventBus } from "../../application/events.js";
import { assignTask } from "../../application/services/assign-task.js";
import { reportStatus } from "../../application/services/report-status.js";
import type { ApiRequest, ApiResponse } from "../types.js";
import { appErr } from "../types.js";
import { ERROR_CODE } from "../../application/result.js";
import type {
  AssignTaskSchema,
  GetTaskSchema,
  GetTasksByConversationSchema,
  ReportStatusSchema,
  TaskResponse,
} from "../schemas/task-schemas.js";

export function createTaskController(db: DbClient, eventBus: EventBus) {
  return {
    async assign(
      req: ApiRequest<AssignTaskSchema>,
    ): Promise<ApiResponse<TaskResponse>> {
      const result = assignTask(db, req.body);
      if (!result.ok) return appErr(result.error);
      eventBus.emit({
        type: "task:created",
        data: { id: result.data.id, conversation: result.data.conversation },
      });
      return { ok: true, data: result.data };
    },

    async get(
      req: ApiRequest<GetTaskSchema>,
    ): Promise<ApiResponse<TaskResponse>> {
      const task = db.getTask(req.params.id);
      if (!task) {
        return appErr({
          code: ERROR_CODE.notFound,
          message: `Task ${req.params.id} not found`,
          statusHint: 404,
        });
      }
      return { ok: true, data: task };
    },

    async getByConversation(
      req: ApiRequest<GetTasksByConversationSchema>,
    ): Promise<ApiResponse<TaskResponse[]>> {
      const tasks = db.getTasksByConversation(req.params.conversation);
      return { ok: true, data: tasks };
    },

    async report(
      req: ApiRequest<ReportStatusSchema>,
    ): Promise<ApiResponse<{ message_id: string; task_updated: boolean }>> {
      const result = reportStatus(db, req.body);
      if (!result.ok) return appErr(result.error);
      if (result.data.task_updated && req.body.task_id) {
        eventBus.emit({
          type: "task:updated",
          data: {
            id: req.body.task_id,
            conversation: req.body.conversation,
            status: req.body.status,
          },
        });
      }
      return { ok: true, data: result.data };
    },
  };
}
