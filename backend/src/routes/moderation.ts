import { Router } from "express";
import rateLimit from "express-rate-limit";
import { z } from "zod";

import { HttpError } from "../http/errors.js";
import { requireAuth, requirePermission } from "../middleware/authenticate.js";
import {
  applyModerationAction,
  assignReport,
  getReport,
  listModerationActions,
  listReports,
} from "../services/moderation-service.js";

const moderationRouter = Router();
const uuidSchema = z.string().uuid();

function userId(request: { auth?: { userId: string } }) {
  if (!request.auth) throw new HttpError(401, "UNAUTHENTICATED", "Please sign in.");
  return request.auth.userId;
}

function reportId(value: unknown) {
  const parsed = uuidSchema.safeParse(value);
  if (!parsed.success) throw new HttpError(400, "INVALID_ID", "Report ID is invalid.");
  return parsed.data;
}

function parseBody<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = schema.safeParse(value);
  if (!parsed.success) {
    throw new HttpError(400, "VALIDATION_ERROR", parsed.error.issues[0]?.message ?? "Invalid request.");
  }
  return parsed.data;
}

moderationRouter.use(requireAuth);
moderationRouter.use(requirePermission("content:moderate"));
moderationRouter.use(rateLimit({
  windowMs: 60_000,
  limit: process.env.NODE_ENV === "test" ? 100 : 30,
  standardHeaders: true,
  legacyHeaders: false,
}));

moderationRouter.get("/reports", async (request, response) => {
  const status = z.enum(["open", "reviewing", "actioned", "dismissed"])
    .optional()
    .parse(request.query.status);
  const limit = request.query.limit === undefined
    ? 30
    : z.coerce.number().int().min(1).max(100).parse(request.query.limit);
  response.json(await listReports({
    userId: userId(request),
    status,
    limit,
    cursor: z.string().max(300).optional().parse(request.query.cursor),
  }));
});

moderationRouter.get("/reports/:id", async (request, response) => {
  response.json(await getReport(userId(request), reportId(request.params.id)));
});

moderationRouter.patch("/reports/:id/assignment", async (request, response) => {
  const { assigneeId } = parseBody(
    z.object({ assigneeId: uuidSchema.nullable() }).strict(),
    request.body,
  );
  response.json(await assignReport(
    userId(request),
    reportId(request.params.id),
    assigneeId,
  ));
});

moderationRouter.post("/reports/:id/actions", async (request, response) => {
  const input = parseBody(
    z.object({
      action: z.enum([
        "hide_content",
        "restore_content",
        "remove_content",
        "suspend_group",
        "restore_group",
        "restrict_member",
        "dismiss_report",
      ]),
      reason: z.string().trim().min(3).max(1000),
    }).strict(),
    request.body,
  );
  response.json(await applyModerationAction({
    actorId: userId(request),
    reportId: reportId(request.params.id),
    ...input,
  }));
});

moderationRouter.get("/actions", async (request, response) => {
  const targetId = request.query.targetId === undefined
    ? undefined
    : reportId(request.query.targetId);
  const limit = request.query.limit === undefined
    ? 50
    : z.coerce.number().int().min(1).max(100).parse(request.query.limit);
  response.json({
    actions: await listModerationActions(userId(request), targetId, limit),
  });
});

export default moderationRouter;
