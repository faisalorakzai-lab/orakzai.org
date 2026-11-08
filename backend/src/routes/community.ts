import { Router } from "express";
import rateLimit from "express-rate-limit";
import { z } from "zod";

import { requireAuth } from "../middleware/authenticate.js";
import { HttpError } from "../http/errors.js";
import {
  addComment,
  createPost,
  deletePost,
  getPost,
  getCommunitySummary,
  listComments,
  listFeed,
  setAnnouncementPin,
  setPostBookmark,
  setPostReaction,
  recordPostShare,
  updatePost,
  type PostReaction,
  type PostVisibility,
} from "../services/feed-service.js";
import {
  createGroup,
  getGroup,
  groupCategories,
  inviteMember,
  joinGroup,
  leaveGroup,
  listGroupInvitations,
  listGroupMembers,
  listGroups,
  replaceGroupRules,
  respondToInvitation,
  updateGroupDetails,
  updateGroupMember,
} from "../services/group-service.js";
import {
  blockUser,
  createContentReport,
  getNotificationPreferences,
  getMemberProfile,
  getPresenceSettings,
  listBlockedUsers,
  listNotifications,
  markNotificationRead,
  muteTarget,
  notificationPreferenceKeys,
  searchMembers,
  unblockUser,
  unmuteTarget,
  updateNotificationPreferences,
  updatePresenceSettings,
} from "../services/safety-service.js";
import { listOnlineMembers } from "../realtime.js";

const communityRouter = Router();
const writeLimiter = rateLimit({
  windowMs: 60_000,
  limit: process.env.NODE_ENV === "test" ? 100 : 30,
  standardHeaders: true,
  legacyHeaders: false,
});
const idSchema = z.string().uuid();
const categorySchema = z.enum(groupCategories);
const visibilitySchema = z.enum(["public", "private"]);
const postVisibilitySchema = z.enum(["public", "regional", "group", "private"]);

function currentUserId(request: { auth?: { userId: string } }) {
  if (!request.auth) throw new HttpError(401, "UNAUTHENTICATED", "Please sign in.");
  return request.auth.userId;
}

function pathId(value: unknown, name: string) {
  const result = idSchema.safeParse(Array.isArray(value) ? value[0] : value);
  if (!result.success) throw new HttpError(400, "INVALID_ID", `${name} is invalid.`);
  return result.data;
}

function parseBody<T>(schema: z.ZodType<T>, body: unknown): T {
  const result = schema.safeParse(body);
  if (!result.success) {
    throw new HttpError(400, "VALIDATION_ERROR", result.error.issues[0]?.message ?? "Invalid request.");
  }
  return result.data;
}

function parseLimit(value: unknown, defaultValue = 20, max = 50) {
  if (value === undefined) return defaultValue;
  const result = z.coerce.number().int().min(1).max(max).safeParse(value);
  if (!result.success) throw new HttpError(400, "INVALID_LIMIT", `Limit must be between 1 and ${max}.`);
  return result.data;
}

const groupCreateSchema = z.object({
  name: z.string().trim().min(3).max(80),
  description: z.string().trim().max(2000).default(""),
  category: categorySchema,
  visibility: visibilitySchema.default("public"),
  regionId: idSchema.optional(),
  districtId: idSchema.optional(),
  qoumId: idSchema.optional(),
  villageId: idSchema.optional(),
}).strict();

const groupUpdateSchema = z.object({
  name: z.string().trim().min(3).max(80).optional(),
  description: z.string().trim().max(2000).optional(),
  category: categorySchema.optional(),
  visibility: visibilitySchema.optional(),
}).strict().refine((value) => Object.keys(value).length > 0, "Provide at least one group field.");

communityRouter.use(requireAuth);
communityRouter.use("/posts", writeLimiter);
communityRouter.use("/groups", writeLimiter);
communityRouter.use("/reports", writeLimiter);
communityRouter.use("/blocks", writeLimiter);
communityRouter.use("/mutes", writeLimiter);

communityRouter.get("/feed", async (request, response) => {
  const search = z.string().trim().max(120).optional().parse(request.query.search);
  const cursor = z.string().max(300).optional().parse(request.query.cursor);
  const groupId = request.query.groupId === undefined ? undefined : pathId(request.query.groupId, "Group");
  const regionId = request.query.regionId === undefined ? undefined : pathId(request.query.regionId, "Region");
  response.json(await listFeed({
    userId: currentUserId(request),
    limit: parseLimit(request.query.limit),
    cursor,
    groupId,
    regionId,
    search,
  }));
});

communityRouter.get("/summary", async (request, response) => {
  response.setHeader("Cache-Control", "private, no-store");
  response.json(await getCommunitySummary(currentUserId(request)));
});

communityRouter.get("/announcements", async (request, response) => {
  response.json(await listFeed({
    userId: currentUserId(request),
    limit: parseLimit(request.query.limit),
    cursor: z.string().max(300).optional().parse(request.query.cursor),
    announcementsOnly: true,
  }));
});

communityRouter.get("/members/search", async (request, response) => {
  const q = z.string().trim().min(2).max(80).parse(request.query.q);
  response.json({
    members: await searchMembers(currentUserId(request), q, parseLimit(request.query.limit, 20, 50)),
  });
});

communityRouter.get("/members/:memberId", async (request, response) => {
  response.json(await getMemberProfile(
    currentUserId(request),
    pathId(request.params.memberId, "Member"),
  ));
});

communityRouter.get("/online-members", async (request, response) => {
  response.json({ members: await listOnlineMembers(currentUserId(request)) });
});

communityRouter.get("/notifications", async (request, response) => {
  response.json({
    notifications: await listNotifications(
      currentUserId(request),
      parseLimit(request.query.limit, 30, 100),
    ),
  });
});

communityRouter.get("/notifications/preferences", async (request, response) => {
  response.json({ preferences: await getNotificationPreferences(currentUserId(request)) });
});

communityRouter.patch("/notifications/preferences", async (request, response) => {
  const preferenceKeys = notificationPreferenceKeys();
  const inputSchema = z.object(Object.fromEntries(
    preferenceKeys.map((key) => [key, z.boolean().optional()]),
  )).strict().refine((value) => Object.values(value).some((item) => item !== undefined));
  response.json({
    preferences: await updateNotificationPreferences(
      currentUserId(request),
      parseBody(inputSchema, request.body),
    ),
  });
});

communityRouter.post("/notifications/:notificationId/read", async (request, response) => {
  response.json(await markNotificationRead(
    currentUserId(request),
    pathId(request.params.notificationId, "Notification"),
  ));
});

communityRouter.get("/presence/settings", async (request, response) => {
  response.json({ settings: await getPresenceSettings(currentUserId(request)) });
});

communityRouter.patch("/presence/settings", async (request, response) => {
  const input = parseBody(
    z.object({
      showOnlineStatus: z.boolean().optional(),
      shareLastSeen: z.boolean().optional(),
    }).strict().refine((value) => Object.values(value).some((item) => item !== undefined)),
    request.body,
  );
  response.json({ settings: await updatePresenceSettings(currentUserId(request), input) });
});

communityRouter.get("/blocks", async (request, response) => {
  response.json({ blockedMembers: await listBlockedUsers(currentUserId(request)) });
});

communityRouter.post("/blocks/:memberId", async (request, response) => {
  response.json(await blockUser(
    currentUserId(request),
    pathId(request.params.memberId, "Member"),
  ));
});

communityRouter.delete("/blocks/:memberId", async (request, response) => {
  response.json(await unblockUser(
    currentUserId(request),
    pathId(request.params.memberId, "Member"),
  ));
});

communityRouter.put("/mutes", async (request, response) => {
  const input = parseBody(
    z.object({
      targetType: z.enum(["user", "group", "conversation"]),
      targetId: idSchema,
      mutedUntil: z.string().datetime().nullable().optional(),
    }).strict(),
    request.body,
  );
  response.json(await muteTarget(
    currentUserId(request),
    input.targetType,
    input.targetId,
    input.mutedUntil,
  ));
});

communityRouter.delete("/mutes/:targetType/:targetId", async (request, response) => {
  const targetType = z.enum(["user", "group", "conversation"]).parse(request.params.targetType);
  response.json(await unmuteTarget(
    currentUserId(request),
    targetType,
    pathId(request.params.targetId, "Muted target"),
  ));
});

communityRouter.post("/reports", async (request, response) => {
  const input = parseBody(
    z.object({
      targetType: z.enum(["post", "comment", "message", "group", "user"]),
      targetId: idSchema,
      category: z.enum([
        "spam", "harassment", "threats", "hate_abuse", "fraud_scams",
        "impersonation", "inappropriate", "other",
      ]),
      details: z.string().trim().max(2000).default(""),
    }).strict(),
    request.body,
  );
  response.status(201).json(await createContentReport({
    reporterId: currentUserId(request),
    ...input,
    details: input.details ?? "",
  }));
});

communityRouter.get("/regional/:regionId/feed", async (request, response) => {
  response.json(await listFeed({
    userId: currentUserId(request),
    limit: parseLimit(request.query.limit),
    cursor: z.string().max(300).optional().parse(request.query.cursor),
    regionId: pathId(request.params.regionId, "Region"),
  }));
});

communityRouter.post("/posts", async (request, response) => {
  const input = parseBody(
    z.object({
      body: z.string().max(10000),
      visibility: postVisibilitySchema,
      groupId: idSchema.optional(),
      regionId: idSchema.optional(),
      mediaIds: z.array(idSchema).max(10).optional(),
      isAnnouncement: z.boolean().optional(),
    }).strict(),
    request.body,
  );
  response.status(201).json(await createPost(currentUserId(request), input as {
    body: string;
    visibility: PostVisibility;
    groupId?: string;
    regionId?: string;
    mediaIds?: string[];
    isAnnouncement?: boolean;
  }));
});

communityRouter.get("/posts/:postId", async (request, response) => {
  response.json(await getPost(currentUserId(request), pathId(request.params.postId, "Post")));
});

communityRouter.patch("/posts/:postId", async (request, response) => {
  const { body } = parseBody(z.object({ body: z.string().trim().min(1).max(10000) }).strict(), request.body);
  response.json(await updatePost(currentUserId(request), pathId(request.params.postId, "Post"), body));
});

communityRouter.delete("/posts/:postId", async (request, response) => {
  response.json(await deletePost(currentUserId(request), pathId(request.params.postId, "Post")));
});

communityRouter.get("/posts/:postId/comments", async (request, response) => {
  response.json(await listComments(
    currentUserId(request),
    pathId(request.params.postId, "Post"),
    parseLimit(request.query.limit, 30, 100),
    z.string().max(300).optional().parse(request.query.cursor),
  ));
});

communityRouter.post("/posts/:postId/comments", async (request, response) => {
  const input = parseBody(
    z.object({
      body: z.string().trim().min(1).max(4000),
      parentCommentId: idSchema.optional(),
    }).strict(),
    request.body,
  );
  response.status(201).json(await addComment(
    currentUserId(request),
    pathId(request.params.postId, "Post"),
    input,
  ));
});

communityRouter.post("/posts/:postId/reactions", async (request, response) => {
  const { reaction } = parseBody(
    z.object({ reaction: z.enum(["like", "support", "celebrate", "care"]) }).strict(),
    request.body,
  );
  response.json(await setPostReaction(
    currentUserId(request),
    pathId(request.params.postId, "Post"),
    reaction as PostReaction,
  ));
});

communityRouter.post("/posts/:postId/share", async (request, response) => {
  response.json(await recordPostShare(
    currentUserId(request),
    pathId(request.params.postId, "Post"),
  ));
});

communityRouter.put("/posts/:postId/bookmark", async (request, response) => {
  const { saved } = parseBody(z.object({ saved: z.boolean() }).strict(), request.body);
  response.json(await setPostBookmark(
    currentUserId(request),
    pathId(request.params.postId, "Post"),
    saved,
  ));
});

communityRouter.put("/posts/:postId/announcement", async (request, response) => {
  const { pinned } = parseBody(z.object({ pinned: z.boolean() }).strict(), request.body);
  response.json(await setAnnouncementPin(
    currentUserId(request),
    pathId(request.params.postId, "Post"),
    pinned,
  ));
});

communityRouter.get("/groups/invitations", async (request, response) => {
  response.json({ invitations: await listGroupInvitations(currentUserId(request)) });
});

communityRouter.post("/groups", async (request, response) => {
  const input = parseBody(groupCreateSchema, request.body);
  response.status(201).json(await createGroup(currentUserId(request), {
    ...input,
    description: input.description ?? "",
    visibility: input.visibility ?? "public",
  }));
});

communityRouter.get("/groups", async (request, response) => {
  const search = z.string().trim().max(120).optional().parse(request.query.search);
  const category = categorySchema.optional().parse(request.query.category);
  const mine = request.query.mine === "true";
  response.json(await listGroups({
    userId: currentUserId(request),
    search,
    category,
    mine,
    limit: parseLimit(request.query.limit),
    cursor: z.string().max(300).optional().parse(request.query.cursor),
  }));
});

communityRouter.get("/groups/:groupId/members", async (request, response) => {
  response.json({
    members: await listGroupMembers(
      currentUserId(request),
      pathId(request.params.groupId, "Group"),
    ),
  });
});

communityRouter.post("/groups/:groupId/join", async (request, response) => {
  response.json(await joinGroup(
    currentUserId(request),
    pathId(request.params.groupId, "Group"),
  ));
});

communityRouter.post("/groups/:groupId/leave", async (request, response) => {
  response.json(await leaveGroup(
    currentUserId(request),
    pathId(request.params.groupId, "Group"),
  ));
});

communityRouter.post("/groups/:groupId/invite", async (request, response) => {
  const { inviteeId } = parseBody(z.object({ inviteeId: idSchema }).strict(), request.body);
  response.status(201).json(await inviteMember(
    currentUserId(request),
    pathId(request.params.groupId, "Group"),
    inviteeId,
  ));
});

communityRouter.patch("/groups/:groupId/members/:memberId", async (request, response) => {
  const input = parseBody(
    z.object({
      action: z.enum(["remove", "role"]),
      role: z.enum(["admin", "moderator", "member"]).optional(),
    }).strict(),
    request.body,
  );
  response.json(await updateGroupMember(
    currentUserId(request),
    pathId(request.params.groupId, "Group"),
    pathId(request.params.memberId, "Member"),
    input,
  ));
});

communityRouter.patch("/groups/:groupId", async (request, response) => {
  const input = parseBody(groupUpdateSchema, request.body);
  response.json(await updateGroupDetails(
    currentUserId(request),
    pathId(request.params.groupId, "Group"),
    input,
  ));
});

communityRouter.put("/groups/:groupId/rules", async (request, response) => {
  const { rules } = parseBody(
    z.object({
      rules: z.array(z.object({
        title: z.string().trim().min(2).max(120),
        body: z.string().trim().min(1).max(1000),
      }).strict()).max(30),
    }).strict(),
    request.body,
  );
  response.json(await replaceGroupRules(
    currentUserId(request),
    pathId(request.params.groupId, "Group"),
    rules,
  ));
});

communityRouter.get("/groups/:groupId", async (request, response) => {
  response.json(await getGroup(
    currentUserId(request),
    pathId(request.params.groupId, "Group"),
  ));
});

communityRouter.post("/invitations/:invitationId/respond", async (request, response) => {
  const { accept } = parseBody(z.object({ accept: z.boolean() }).strict(), request.body);
  response.json(await respondToInvitation(
    currentUserId(request),
    pathId(request.params.invitationId, "Invitation"),
    accept,
  ));
});

export default communityRouter;
