import { Router } from "express";
import rateLimit from "express-rate-limit";
import { z } from "zod";

import { HttpError } from "../http/errors.js";
import { requireAuth } from "../middleware/authenticate.js";
import {
  createDirectConversation,
  deleteMessage,
  editMessage,
  forwardMessage,
  getConversation,
  listConversations,
  listMessages,
  markConversationRead,
  markMessagesDelivered,
  searchMessages,
  sendMessage,
  setMessageReaction,
} from "../services/message-service.js";
import {
  publishMessage,
  publishReadReceipt,
  publishDeliveryReceipt,
} from "../realtime.js";

const messagesRouter = Router();
const writeLimiter = rateLimit({
  windowMs: 60_000,
  limit: process.env.NODE_ENV === "test" ? 100 : 60,
  standardHeaders: true,
  legacyHeaders: false,
});
const uuidSchema = z.string().uuid();

function userId(request: { auth?: { userId: string } }) {
  if (!request.auth) throw new HttpError(401, "UNAUTHENTICATED", "Please sign in.");
  return request.auth.userId;
}

function pathId(value: unknown, label: string) {
  const parsed = uuidSchema.safeParse(Array.isArray(value) ? value[0] : value);
  if (!parsed.success) throw new HttpError(400, "INVALID_ID", `${label} is invalid.`);
  return parsed.data;
}

function parseLimit(value: unknown, fallback = 30, max = 100) {
  if (value === undefined) return fallback;
  const parsed = z.coerce.number().int().min(1).max(max).safeParse(value);
  if (!parsed.success) throw new HttpError(400, "INVALID_LIMIT", `Limit must be between 1 and ${max}.`);
  return parsed.data;
}

function parseBody<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = schema.safeParse(value);
  if (!parsed.success) {
    throw new HttpError(400, "VALIDATION_ERROR", parsed.error.issues[0]?.message ?? "Invalid request.");
  }
  return parsed.data;
}

messagesRouter.use(requireAuth);
messagesRouter.use(writeLimiter);

messagesRouter.get("/conversations", async (request, response) => {
  const search = z.string().trim().max(120).optional().parse(request.query.search);
  response.json({ conversations: await listConversations(userId(request), search) });
});

messagesRouter.post("/conversations", async (request, response) => {
  const { recipientId } = parseBody(
    z.object({ recipientId: uuidSchema }).strict(),
    request.body,
  );
  response.status(201).json(await createDirectConversation(userId(request), recipientId));
});

messagesRouter.get("/conversations/:conversationId", async (request, response) => {
  response.json(await getConversation(
    userId(request),
    pathId(request.params.conversationId, "Conversation"),
  ));
});

messagesRouter.get("/conversations/:conversationId/messages", async (request, response) => {
  response.json(await listMessages(
    userId(request),
    pathId(request.params.conversationId, "Conversation"),
    parseLimit(request.query.limit),
    z.string().max(300).optional().parse(request.query.cursor),
  ));
});

messagesRouter.post("/conversations/:conversationId/messages", async (request, response) => {
  const input = parseBody(
    z.object({
      body: z.string().max(10000).default(""),
      replyToId: uuidSchema.optional(),
      mediaIds: z.array(uuidSchema).max(10).optional(),
      clientNonce: uuidSchema.optional(),
    }).strict(),
    request.body,
  );
  const message = await sendMessage(
    userId(request),
    pathId(request.params.conversationId, "Conversation"),
    {
      ...input,
      body: input.body ?? "",
    },
  );
  await publishMessage(message.conversationId, message);
  response.status(201).json({ message });
});

messagesRouter.post(
  "/conversations/:conversationId/messages/:messageId/forward",
  async (request, response) => {
    const input = parseBody(
      z.object({
        targetConversationId: uuidSchema,
        clientNonce: uuidSchema,
      }).strict(),
      request.body,
    );
    const message = await forwardMessage(
      userId(request),
      pathId(request.params.conversationId, "Conversation"),
      pathId(request.params.messageId, "Message"),
      input.targetConversationId,
      input.clientNonce,
    );
    await publishMessage(message.conversationId, message);
    response.status(201).json({ message });
  },
);

messagesRouter.post("/conversations/:conversationId/read", async (request, response) => {
  const result = await markConversationRead(
    userId(request),
    pathId(request.params.conversationId, "Conversation"),
  );
  publishReadReceipt(result.conversationId, userId(request), result.readAt);
  response.json(result);
});

messagesRouter.post("/conversations/:conversationId/delivered", async (request, response) => {
  const { messageIds } = parseBody(
    z.object({ messageIds: z.array(uuidSchema).min(1).max(100) }).strict(),
    request.body,
  );
  const result = await markMessagesDelivered(
    userId(request),
    pathId(request.params.conversationId, "Conversation"),
    messageIds,
  );
  publishDeliveryReceipt(result.conversationId, userId(request), result.deliveredIds);
  response.json(result);
});

messagesRouter.patch(
  "/conversations/:conversationId/messages/:messageId",
  async (request, response) => {
    const { body } = parseBody(
      z.object({ body: z.string().trim().min(1).max(10000) }).strict(),
      request.body,
    );
    response.json(await editMessage(
      userId(request),
      pathId(request.params.conversationId, "Conversation"),
      pathId(request.params.messageId, "Message"),
      body,
    ));
  },
);

messagesRouter.delete(
  "/conversations/:conversationId/messages/:messageId",
  async (request, response) => {
    response.json(await deleteMessage(
      userId(request),
      pathId(request.params.conversationId, "Conversation"),
      pathId(request.params.messageId, "Message"),
    ));
  },
);

messagesRouter.post(
  "/conversations/:conversationId/messages/:messageId/reactions",
  async (request, response) => {
    const { reaction } = parseBody(
      z.object({ reaction: z.enum(["like", "love", "laugh", "support", "celebrate"]) }).strict(),
      request.body,
    );
    response.json(await setMessageReaction(
      userId(request),
      pathId(request.params.conversationId, "Conversation"),
      pathId(request.params.messageId, "Message"),
      reaction,
    ));
  },
);

messagesRouter.get(
  "/conversations/:conversationId/search",
  async (request, response) => {
    const query = z.string().trim().min(1).max(120).parse(request.query.q);
    response.json(await searchMessages(
      userId(request),
      pathId(request.params.conversationId, "Conversation"),
      query,
      parseLimit(request.query.limit, 20, 50),
    ));
  },
);

export default messagesRouter;
